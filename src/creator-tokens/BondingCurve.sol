// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/erc20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { Actions } from "v4-periphery/src/libraries/Actions.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { LiquidityAmounts } from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import { SwapFeeHook } from "./SwapFeeHook.sol";
import { BaseUniswapDeployments } from "./lib/BaseUniswapDeployments.sol";
import { FactoryConfig } from "./lib/FactoryConfig.sol";
import { LinearCurveMathV4 } from "./lib/LinearCurveMath.sol";

contract BondingCurve {
    struct BondingMetadata {
        address creator;
        address characterToken;
        uint256 graduationThreshold;
        uint256 slope;
        uint256 basePrice;
        uint256 maxSupply;
        address vestingWallet;
        bool graduated;
    }

    address constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    IPoolManager public immutable POOL_MANAGER = IPoolManager(BaseUniswapDeployments.POOL_MANAGER);
    IPositionManager public immutable POSITION_MANAGER =
        IPositionManager(payable(BaseUniswapDeployments.POSITION_MANAGER));

    uint24 public constant POOL_FEE = 0;
    int24 public constant TICK_SPACING = 200;
    uint64 public constant MIN_PURCHASE_FLK = 1e17;

    BondingMetadata public metadata;
    uint256 public characterTokensSold;

    event Buy(address indexed user, uint256 parentIn, uint256 characterOut);
    event Sell(address indexed user, uint256 characterIn, uint256 parentOut);
    event Graduated(uint256 tokenId, uint256 parentTokenBalance, uint256 characterTokenBalance);

    error AlreadyGraduated();
    error ZeroInput();
    error SlippageExceeded();
    error NotEnoughFLK();
    error TokenTransferFailed();

    constructor(
        address _creator,
        address _characterToken,
        uint256 _graduationThreshold,
        uint256 _basePrice,
        uint256 _characterSupply,
        address _vestingWallet
    ) {
        uint256 finalPrice = LinearCurveMathV4.finalPrice(
            _graduationThreshold,
            _characterSupply,
            _basePrice,
            FactoryConfig.CREATOR_COIN_DECIMALS,
            FactoryConfig.FLK_DECIMALS
        );

        uint256 slope = LinearCurveMathV4.slope(
            finalPrice,
            _basePrice,
            _characterSupply,
            FactoryConfig.CREATOR_COIN_DECIMALS,
            FactoryConfig.FLK_DECIMALS
        );

        metadata = BondingMetadata({
            creator: _creator,
            characterToken: _characterToken,
            graduationThreshold: _graduationThreshold,
            slope: slope,
            basePrice: _basePrice,
            maxSupply: _characterSupply,
            vestingWallet: _vestingWallet,
            graduated: false
        });
    }

    /// @notice Buy character tokens with parent tokens
    /// @param parentAmountIn Amount of parent tokens to spend
    /// @param minCharacterOut Minimum character tokens to receive
    function buy(uint256 parentAmountIn, uint256 minCharacterOut) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (parentAmountIn < MIN_PURCHASE_FLK) revert NotEnoughFLK();

        uint256 characterOut = LinearCurveMathV4.calculateBuyAmount(
            parentAmountIn,
            characterTokensSold,
            metadata.basePrice,
            metadata.slope,
            FactoryConfig.CREATOR_COIN_DECIMALS,
            FactoryConfig.FLK_DECIMALS
        );

        // Cap to available character token supply
        uint256 available = IERC20(metadata.characterToken).balanceOf(address(this));
        if (characterOut > available) {
            characterOut = available;
            parentAmountIn = LinearCurveMathV4.calculateBuyCost(
                characterOut,
                characterTokensSold,
                metadata.basePrice,
                metadata.slope,
                FactoryConfig.CREATOR_COIN_DECIMALS,
                FactoryConfig.FLK_DECIMALS
            );
        }

        if (characterOut < minCharacterOut) revert SlippageExceeded();

        require(
            IERC20(FactoryConfig.FLK).transferFrom(msg.sender, address(this), parentAmountIn),
            TokenTransferFailed()
        );
        require(
            IERC20(metadata.characterToken).transfer(msg.sender, characterOut),
            TokenTransferFailed()
        );

        characterTokensSold += characterOut;

        emit Buy(msg.sender, parentAmountIn, characterOut);

        uint256 currentBalance = IERC20(FactoryConfig.FLK).balanceOf(address(this));
        if (currentBalance >= metadata.graduationThreshold) {
            _graduate();
        }
    }

    /// @notice Sell character tokens for parent tokens
    /// @param characterAmountIn Amount of character tokens to sell
    /// @param minParentOut Minimum parent tokens to receive
    function sell(uint256 characterAmountIn, uint256 minParentOut) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (characterAmountIn < 1e17) revert ZeroInput();

        uint256 parentOut = LinearCurveMathV4.calculateSellAmount(
            characterAmountIn,
            characterTokensSold,
            metadata.basePrice,
            metadata.slope,
            FactoryConfig.CREATOR_COIN_DECIMALS,
            FactoryConfig.FLK_DECIMALS
        );

        uint256 available = IERC20(FactoryConfig.FLK).balanceOf(address(this));
        if (parentOut > available) {
            parentOut = available;
            characterAmountIn = LinearCurveMathV4.calculateSellCost(
                parentOut,
                characterTokensSold,
                metadata.basePrice,
                metadata.slope,
                FactoryConfig.CREATOR_COIN_DECIMALS,
                FactoryConfig.FLK_DECIMALS
            );
        }

        if (parentOut < minParentOut) revert SlippageExceeded();

        require(
            IERC20(metadata.characterToken)
                .transferFrom(msg.sender, address(this), characterAmountIn),
            TokenTransferFailed()
        );
        require(IERC20(FactoryConfig.FLK).transfer(msg.sender, parentOut), TokenTransferFailed());

        characterTokensSold -= characterAmountIn;

        emit Sell(msg.sender, characterAmountIn, parentOut);
    }

    function _graduate() internal {
        uint256 parentBalance = IERC20(FactoryConfig.FLK).balanceOf(address(this));
        uint256 characterBalance = IERC20(metadata.characterToken).balanceOf(address(this));

        // Sort tokens and amounts, calculate price from actual balances
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint160 startingPrice;

        if (FactoryConfig.FLK < metadata.characterToken) {
            // token0=parent, token1=character
            // sqrtPriceX96 = sqrt(character/parent) * 2^96
            token0 = FactoryConfig.FLK;
            token1 = metadata.characterToken;
            amount0 = parentBalance;
            amount1 = characterBalance;

            // Convert character balance to parent decimals for ratio
            uint256 characterInParentDecimals = LinearCurveMathV4.convertPrice(
                characterBalance, FactoryConfig.CREATOR_COIN_DECIMALS, FactoryConfig.FLK_DECIMALS
            );

            uint256 sqrtCharacter = Math.sqrt(characterInParentDecimals);
            uint256 sqrtParent = Math.sqrt(parentBalance);
            startingPrice = SafeCast.toUint160((sqrtCharacter * (2 ** 96)) / sqrtParent);
        } else {
            // token0=character, token1=parent
            // sqrtPriceX96 = sqrt(parent/character) * 2^96
            token0 = metadata.characterToken;
            token1 = FactoryConfig.FLK;
            amount0 = characterBalance;
            amount1 = parentBalance;

            // Convert parent balance to character decimals for ratio
            uint256 parentInCharacterDecimals = LinearCurveMathV4.convertPrice(
                parentBalance, FactoryConfig.FLK_DECIMALS, FactoryConfig.CREATOR_COIN_DECIMALS
            );

            uint256 sqrtParent = Math.sqrt(parentInCharacterDecimals);
            uint256 sqrtCharacter = Math.sqrt(characterBalance);

            startingPrice = SafeCast.toUint160((sqrtParent * (2 ** 96)) / sqrtCharacter);
        }

        // Validate price range
        require(
            startingPrice >= TickMath.MIN_SQRT_PRICE && startingPrice <= TickMath.MAX_SQRT_PRICE,
            "Invalid starting price"
        );

        address hookAddress = _deployHook();

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hookAddress)
        });

        POOL_MANAGER.initialize(poolKey, startingPrice);

        _mintLiquidityPosition(poolKey, token0, token1, amount0, amount1, startingPrice);

        metadata.graduated = true;
        emit Graduated(0, parentBalance, characterBalance);
    }

    function _mintLiquidityPosition(
        PoolKey memory poolKey,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) private {
        // Intentional: rounding MIN_TICK down to nearest TICK_SPACING multiple
        // forge-lint: disable-next-line(divide-before-multiply)
        int24 tickLower = (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING;
        // forge-lint: disable-next-line(divide-before-multiply)
        int24 tickUpper = (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING;

        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        IERC20(token0).approve(BaseUniswapDeployments.PERMIT2, type(uint256).max);
        IERC20(token1).approve(BaseUniswapDeployments.PERMIT2, type(uint256).max);

        uint48 expiration = type(uint48).max;
        IAllowanceTransfer(BaseUniswapDeployments.PERMIT2)
            .approve(token0, address(POSITION_MANAGER), type(uint160).max, expiration);
        IAllowanceTransfer(BaseUniswapDeployments.PERMIT2)
            .approve(token1, address(POSITION_MANAGER), type(uint160).max, expiration);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            liquidity,
            SafeCast.toUint128(amount0 + 1),
            SafeCast.toUint128(amount1 + 1),
            address(this),
            bytes("")
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        POSITION_MANAGER.modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _deployHook() internal returns (address) {
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);

        bytes memory constructorArgs = abi.encode(
            FactoryConfig.FOUNDATION,
            metadata.creator,
            FactoryConfig.FLK,
            metadata.characterToken,
            metadata.vestingWallet
        );
        bytes memory creationCode = type(SwapFeeHook).creationCode;

        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, creationCode, constructorArgs);

        SwapFeeHook hook = new SwapFeeHook{
            salt: salt
        }(
            FactoryConfig.FOUNDATION,
            metadata.creator,
            FactoryConfig.FLK,
            metadata.characterToken,
            metadata.vestingWallet
        );
        require(address(hook) == hookAddress, "Hook address mismatch");

        return hookAddress;
    }
}
