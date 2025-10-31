// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BaseHook } from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AntiFlipFeeLib } from "../libraries/AntiFlipFeeLib.sol";
import { Config } from "../libraries/Config.sol";

/**
 * @title UniversalAntiFlipFeeHook
 * @author Fleek
 * @notice Universal Uniswap V4 hook serving all creator token pairs
 *
 * This hook serves multiple creator token pools, maintaining separate state for each token.
 * Bonding curves register their tokens during graduation, and the hook applies token-specific
 * fees and anti-flip logic.
 *
 * Total Fees by Transaction Type:
 *   Buys: 2% of FLK spent
 *   Sells (after window expires): 2% of FLK received
 *   Sells (within window): 12% of FLK received
 *
 * Implementation Notes
 * ====================
 * - Single hook instance serves all creator tokens
 * - Each token has its own creator, vesting wallet, and graduation timestamp
 * - Only authorized bonding curves (verified via factory) can register tokens
 * - Buy timestamps tracked per-token per-user
 *
 */
contract UniversalAntiFlipFeeHook is BaseHook {
    address public immutable FACTORY;

    mapping(address => address) public tokenToCreator;
    mapping(address => address) public tokenToVestingWallet;
    mapping(address => uint256) public tokenGraduationTimestamp;

    /// @notice Tracks last buy timestamp per token per user (token => user => timestamp)
    mapping(address => mapping(address => uint256)) public userLastBuy;

    /// @notice Tracks claimable FLK fees for each address (foundation and creators)
    mapping(address => uint256) public claimableFees;

    /// @notice Emitted when a token is registered with the hook
    event TokenRegistered(
        address indexed token,
        address indexed creator,
        address indexed vestingWallet,
        uint256 graduationTimestamp
    );

    /// @notice Emitted when fees are accumulated for a recipient
    event FeesAccumulated(address indexed recipient, uint256 amount);

    /// @notice Emitted when fees are claimed
    event FeesClaimed(address indexed recipient, uint256 amount);

    error NotAuthorizedBondingCurve();
    error TokenAlreadyRegistered();
    error TokenNotRegistered();
    error NoFeesToClaim();
    error FeeCaptureFailed();
    error UnableToClaimFees();

    /**
     * @notice Creates the universal hook
     * @param _factory Address of CreatorTokenFactory for authorization
     * @param _poolManager Address of Uniswap V4 PoolManager
     */
    constructor(address _factory, address _poolManager) BaseHook(IPoolManager(_poolManager)) {
        FACTORY = _factory;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Registers a creator token with the hook
     * @dev Only callable by the authorized bonding curve for this token (verified via factory)
     * @param token Address of the creator token
     * @param creator Address to receive creator fees
     * @param vestingWallet Address of vesting wallet for anti-flip calculation
     */
    function registerToken(address token, address creator, address vestingWallet) external {
        (bool success, bytes memory data) =
            FACTORY.staticcall(abi.encodeWithSignature("bondingCurveFor(address)", token));

        if (!success || data.length == 0) {
            revert NotAuthorizedBondingCurve();
        }

        address authorizedBondingCurve = abi.decode(data, (address));
        if (msg.sender != authorizedBondingCurve) {
            revert NotAuthorizedBondingCurve();
        }

        if (tokenToCreator[token] != address(0)) {
            revert TokenAlreadyRegistered();
        }

        tokenToCreator[token] = creator;
        tokenToVestingWallet[token] = vestingWallet;
        tokenGraduationTimestamp[token] = block.timestamp;

        emit TokenRegistered(token, creator, vestingWallet, block.timestamp);
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4, int128) {
        address creatorToken = _identifyCreatorToken(key.currency0, key.currency1);
        address creator = tokenToCreator[creatorToken];

        if (creator == address(0)) {
            revert TokenNotRegistered();
        }

        address user = hookData.length >= 20 ? address(bytes20(hookData[0:20])) : sender;

        bool flkIsToken0 = Currency.unwrap(key.currency0) == Config.FLK();
        bool isBuy = params.zeroForOne ? flkIsToken0 : !flkIsToken0;

        if (isBuy) {
            userLastBuy[creatorToken][user] = block.timestamp;
        }

        int128 flkDelta = flkIsToken0 ? delta.amount0() : delta.amount1();
        uint256 absFlkAmount;
        if (flkDelta < 0) {
            // casting to 'uint256' is safe because flkDelta is negative, negation yields positive value within int256 range
            // forge-lint: disable-next-line(unsafe-typecast)
            absFlkAmount = uint256(-int256(flkDelta));
        } else {
            // casting to 'uint256' is safe because flkDelta is non-negative
            // forge-lint: disable-next-line(unsafe-typecast)
            absFlkAmount = uint256(int256(flkDelta));
        }
        uint256 totalFee = _computeFees(user, isBuy, creatorToken, absFlkAmount);
        if (totalFee == 0) {
            return (this.afterSwap.selector, 0);
        }

        require(
            IERC20(Config.FLK()).transferFrom(user, address(this), totalFee), FeeCaptureFailed()
        );

        (uint256 foundationBps, uint256 creatorBps) =
            AntiFlipFeeLib.getFeeRates(creator, creatorToken, tokenToVestingWallet[creatorToken]);

        uint256 foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
        uint256 creatorFee = totalFee - foundationFee;

        claimableFees[Config.FOUNDATION()] += foundationFee;
        claimableFees[creator] += creatorFee;

        emit FeesAccumulated(Config.FOUNDATION(), foundationFee);
        emit FeesAccumulated(creator, creatorFee);

        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Computes fee amounts for a swap
     */
    function _computeFees(address sender, bool isBuy, address creatorToken, uint256 absFlkDelta)
        internal
        view
        returns (uint256 totalFee)
    {
        (totalFee,,) = AntiFlipFeeLib.calculateFees(
            absFlkDelta,
            sender,
            isBuy,
            userLastBuy[creatorToken],
            tokenToCreator[creatorToken],
            creatorToken,
            tokenToVestingWallet[creatorToken],
            tokenGraduationTimestamp[creatorToken]
        );
    }

    /**
     * @notice Allows foundation and creators to claim their accumulated fees
     * @dev Transfers FLK from hook's balance to caller
     */
    function claimFees() external {
        uint256 amount = claimableFees[msg.sender];
        if (amount == 0) {
            revert NoFeesToClaim();
        }

        claimableFees[msg.sender] = 0;

        require(IERC20(Config.FLK()).transfer(msg.sender, amount), UnableToClaimFees());

        emit FeesClaimed(msg.sender, amount);
    }

    /**
     * @notice Identifies which token is the creator token in the pool
     * @dev Assumes pool contains FLK and a creator token
     * @param currency0 First currency in the pool
     * @param currency1 Second currency in the pool
     * @return Address of the creator token
     */
    function _identifyCreatorToken(Currency currency0, Currency currency1)
        internal
        view
        returns (address)
    {
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);

        if (token0 == Config.FLK()) {
            return token1;
        } else if (token1 == Config.FLK()) {
            return token0;
        } else {
            revert("Pool does not contain FLK");
        }
    }
}
