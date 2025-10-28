// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BaseHook } from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { BeforeSwapDelta, toBeforeSwapDelta } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
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
 * See AntiFlipFeeLib for complete fee structure and anti-snipe mechanism documentation.
 */
contract UniversalAntiFlipFeeHook is BaseHook {
    /// @notice Factory that authorizes bonding curves to register tokens
    address public immutable FACTORY;

    /// @notice Token-specific metadata
    mapping(address => address) public tokenToCreator;
    mapping(address => address) public tokenToVestingWallet;
    mapping(address => uint256) public tokenGraduationTimestamp;

    /// @notice User buy timestamps per token: token => user => timestamp
    mapping(address => mapping(address => uint256)) public userLastBuy;

    /// @notice Emitted when a token is registered with the hook
    event TokenRegistered(
        address indexed token,
        address indexed creator,
        address indexed vestingWallet,
        uint256 graduationTimestamp
    );

    error NotAuthorizedBondingCurve();
    error TokenAlreadyRegistered();
    error TokenNotRegistered();

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
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
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
        // Verify caller is the authorized bonding curve for this token
        // Note: This will call factory's bondingCurveFor(token) which should return msg.sender
        (bool success, bytes memory data) =
            FACTORY.staticcall(abi.encodeWithSignature("bondingCurveFor(address)", token));

        if (!success || data.length == 0) {
            revert NotAuthorizedBondingCurve();
        }

        address authorizedBondingCurve = abi.decode(data, (address));
        if (msg.sender != authorizedBondingCurve) {
            revert NotAuthorizedBondingCurve();
        }

        // Ensure token hasn't been registered yet
        if (tokenToCreator[token] != address(0)) {
            revert TokenAlreadyRegistered();
        }

        // Register token metadata
        tokenToCreator[token] = creator;
        tokenToVestingWallet[token] = vestingWallet;
        tokenGraduationTimestamp[token] = block.timestamp;

        emit TokenRegistered(token, creator, vestingWallet, block.timestamp);
    }

    /**
     * @notice Hook called before every swap - charges fees before swap executes
     * @dev Calculates fees, takes them to recipients, returns delta to charge swapper
     * @return selector Function selector for continued execution
     * @return beforeSwapDelta Fee amount in unspecified currency (charged to swapper)
     * @return lpFee LP fee override (0 = no override)
     */
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        // Identify which token is the creator token
        address creatorToken = _identifyCreatorToken(key.currency0, key.currency1);

        // Get token-specific metadata
        address creator = tokenToCreator[creatorToken];
        if (creator == address(0)) {
            revert TokenNotRegistered();
        }

        // Determine FLK position and swap direction
        bool flkIsToken0 = Currency.unwrap(key.currency0) == Config.FLK();
        bool isBuy = params.zeroForOne ? flkIsToken0 : !flkIsToken0;

        // Calculate fee based on swap amount
        uint256 absAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        uint256 totalFee = _computeFees(sender, isBuy, creatorToken, absAmount);

        if (totalFee == 0) {
            return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // Take fees to recipients
        Currency flkCurrency = flkIsToken0 ? key.currency0 : key.currency1;
        _distributeFees(flkCurrency, totalFee, creator, creatorToken);

        // Return delta - fee is always in FLK
        // For exact input swaps, FLK is the specified currency (params.amountSpecified < 0)
        // For exact output swaps, FLK is the unspecified currency
        // Positive delta means swapper owes more
        int128 feeDelta = SafeCast.toInt128(SafeCast.toInt256(totalFee));

        // Determine if FLK is the specified or unspecified currency
        // zeroForOne=true means selling token0 for token1
        // If exact input (amountSpecified < 0): specified = input token
        // If exact output (amountSpecified > 0): specified = output token
        bool flkIsSpecified = params.amountSpecified < 0
            ? (params.zeroForOne ? flkIsToken0 : !flkIsToken0)  // FLK is input
            : (params.zeroForOne ? !flkIsToken0 : flkIsToken0); // FLK is output

        return (
            this.beforeSwap.selector,
            flkIsSpecified
                ? toBeforeSwapDelta(feeDelta, 0)  // Fee in specified currency
                : toBeforeSwapDelta(0, feeDelta), // Fee in unspecified currency
            0
        );
    }

    /**
     * @notice Hook called after swap - records buy timestamp for anti-flip tracking
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        // Only record timestamp for buys
        bool flkIsToken0 = Currency.unwrap(key.currency0) == Config.FLK();
        bool isBuy = params.zeroForOne ? flkIsToken0 : !flkIsToken0;

        if (isBuy) {
            address creatorToken = _identifyCreatorToken(key.currency0, key.currency1);
            userLastBuy[creatorToken][sender] = block.timestamp;
        }

        return (this.afterSwap.selector, 0);
    }

    /**
     * @notice Computes fee amounts for a swap
     * @dev Separated to reduce stack depth
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
     * @notice Distributes fees to foundation and creator
     * @dev Separated to reduce stack depth.
     *      Takes tokens directly to recipients (creating hook debt).
     *      Returns hookDelta to charge swapper (crediting hook).
     *      Net effect: hook balance = 0, recipients hold the tokens.
     *      Uses AntiFlipFeeLib for dynamic fee split calculation.
     */
    function _distributeFees(
        Currency flkCurrency,
        uint256 totalFee,
        address creator,
        address creatorToken
    ) internal {
        // Get dynamic fee rates based on creator's token holdings
        (uint256 foundationBps, uint256 creatorBps) =
            AntiFlipFeeLib.getFeeRates(creator, creatorToken, tokenToVestingWallet[creatorToken]);

        // Calculate individual fees
        uint256 foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
        uint256 creatorFee = totalFee - foundationFee;

        // Take directly to recipients (hook balance becomes negative)
        poolManager.take(flkCurrency, Config.FOUNDATION(), SafeCast.toUint128(foundationFee));
        poolManager.take(flkCurrency, creator, SafeCast.toUint128(creatorFee));

        // When we return hookDelta=totalFee, swapper pays extra which credits the hook
        // Net: hook balance = -totalFee + totalFee = 0
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
