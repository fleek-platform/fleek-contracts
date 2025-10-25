// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/erc20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
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
import { AntiFlipFeeBase } from "./lib/AntiFlipFeeBase.sol";

contract BondingCurve is AntiFlipFeeBase {
    struct BondingMetadata {
        address creator;
        address characterToken;
        uint256 slope;
        address vestingWallet;
        bool graduated;
    }

    IPoolManager public immutable POOL_MANAGER = IPoolManager(BaseUniswapDeployments.POOL_MANAGER);
    IPositionManager public immutable POSITION_MANAGER =
        IPositionManager(payable(BaseUniswapDeployments.POSITION_MANAGER));

    uint24 public constant POOL_FEE = 0;
    int24 public constant TICK_SPACING = 200;
    uint64 public constant MIN_PURCHASE_FLK = 1e17;

    BondingMetadata public metadata;
    uint256 public characterTokensSold;
    uint256 public immutable DEPLOYMENT_TIMESTAMP;

    event Buy(address indexed user, uint256 parentIn, uint256 characterOut, uint256 fee);
    event Sell(address indexed user, uint256 characterIn, uint256 parentOut, uint256 fee);
    event Graduated(uint256 tokenId, uint256 parentTokenBalance, uint256 characterTokenBalance);
    event FeesCollected(address indexed foundation, address indexed creator, uint256 foundationAmount, uint256 creatorAmount);

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
    ) AntiFlipFeeBase(_creator, _characterToken, _vestingWallet) {
        DEPLOYMENT_TIMESTAMP = block.timestamp;
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
            slope: slope,
            vestingWallet: _vestingWallet,
            graduated: false
        });
    }

    function _getEntropyTimestamp() internal view override returns (uint256) {
        return DEPLOYMENT_TIMESTAMP;
    }

    /// @notice Buy character tokens with parent tokens
    /// @param parentAmountIn Amount of parent tokens to spend on the curve (fees will be added on top)
    /// @param minCharacterOut Minimum character tokens to receive
    function buy(uint256 parentAmountIn, uint256 minCharacterOut) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (parentAmountIn < MIN_PURCHASE_FLK) revert NotEnoughFLK();

        uint256 characterOut = LinearCurveMathV4.calculateBuyAmount(
            parentAmountIn,
            characterTokensSold,
            FactoryConfig.BASE_PRICE,
            metadata.slope,
            FactoryConfig.CREATOR_COIN_DECIMALS,
            FactoryConfig.FLK_DECIMALS
        );

        // Cap to maximum sellable supply (not total balance, which includes LP reserve)
        uint256 maxAvailable = (FactoryConfig.BONDING_CURVE_ALLOCATION / 2) - characterTokensSold;
        uint256 curveCost = parentAmountIn;
        if (characterOut > maxAvailable) {
            characterOut = maxAvailable;
            curveCost = LinearCurveMathV4.calculateBuyCost(
                characterOut,
                characterTokensSold,
                FactoryConfig.BASE_PRICE,
                metadata.slope,
                FactoryConfig.CREATOR_COIN_DECIMALS,
                FactoryConfig.FLK_DECIMALS
            );
        }

        if (characterOut < minCharacterOut) revert SlippageExceeded();

        // Calculate fees on the curve cost
        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = _calculateFees(curveCost, msg.sender, true);
        uint256 totalCost = curveCost + totalFee;

        characterTokensSold += characterOut;

        // Transfer curve cost to contract
        require(
            IERC20(FactoryConfig.FLK).transferFrom(msg.sender, address(this), curveCost),
            TokenTransferFailed()
        );

        // Transfer fees to recipients
        if (totalFee > 0) {
            require(
                IERC20(FactoryConfig.FLK).transferFrom(msg.sender, FactoryConfig.FOUNDATION, foundationFee),
                TokenTransferFailed()
            );
            require(
                IERC20(FactoryConfig.FLK).transferFrom(msg.sender, CREATOR, creatorFee),
                TokenTransferFailed()
            );
            emit FeesCollected(FactoryConfig.FOUNDATION, CREATOR, foundationFee, creatorFee);
        }

        require(
            IERC20(metadata.characterToken).transfer(msg.sender, characterOut),
            TokenTransferFailed()
        );

        userLastBuy[msg.sender] = block.timestamp;

        emit Buy(msg.sender, totalCost, characterOut, totalFee);

        // Graduate when all curve tokens are sold (avoids rounding issues with FLK balance check)
        if (characterTokensSold >= (FactoryConfig.BONDING_CURVE_ALLOCATION / 2)) {
            _graduate();
        }
    }

    /// @notice Sell character tokens for parent tokens
    /// @param characterAmountIn Amount of character tokens to sell
    /// @param minParentOut Minimum parent tokens to receive
    function sell(uint256 characterAmountIn, uint256 minParentOut) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (characterAmountIn < MIN_PURCHASE_FLK) revert ZeroInput();

        uint256 parentOut = LinearCurveMathV4.calculateSellAmount(
            characterAmountIn,
            characterTokensSold,
            FactoryConfig.BASE_PRICE,
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
                FactoryConfig.BASE_PRICE,
                metadata.slope,
                FactoryConfig.CREATOR_COIN_DECIMALS,
                FactoryConfig.FLK_DECIMALS
            );
        }

        if (parentOut < minParentOut) revert SlippageExceeded();

        characterTokensSold -= characterAmountIn;

        require(
            IERC20(metadata.characterToken)
                .transferFrom(msg.sender, address(this), characterAmountIn),
            TokenTransferFailed()
        );

        // Calculate fees on the sell proceeds
        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = _calculateFees(parentOut, msg.sender, false);
        uint256 netParentOut = parentOut - totalFee;

        // Transfer net proceeds to user
        require(IERC20(FactoryConfig.FLK).transfer(msg.sender, netParentOut), TokenTransferFailed());

        // Transfer fees from contract to recipients
        if (totalFee > 0) {
            require(
                IERC20(FactoryConfig.FLK).transfer(FactoryConfig.FOUNDATION, foundationFee),
                TokenTransferFailed()
            );
            require(
                IERC20(FactoryConfig.FLK).transfer(CREATOR, creatorFee),
                TokenTransferFailed()
            );
            emit FeesCollected(FactoryConfig.FOUNDATION, CREATOR, foundationFee, creatorFee);
        }

        emit Sell(msg.sender, characterAmountIn, parentOut, totalFee);
    }

    /// @notice Graduates the bonding curve to Uniswap V4 with full-range liquidity
    /// @dev Creates a single full-range liquidity position from MIN_TICK to MAX_TICK.
    ///
    ///      At graduation with ~225k CreatorTokens and ~20,675 FLK, all tokens are deposited
    ///      into a single LP position providing liquidity across the entire price range.
    ///
    ///      The pool uses 0% swap fee, but the hook takes 2% in FLK only on each swap.
    ///      The LP NFT is burned to 0xdead, permanently locking the liquidity.
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
            startingPrice = SafeCast.toUint160((sqrtCharacter << 96) / sqrtParent);
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

            startingPrice = SafeCast.toUint160((sqrtParent << 96) / sqrtCharacter);
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

        uint256 tokenId =
            _mintAndBurnLiquidityPosition(poolKey, token0, token1, amount0, amount1, startingPrice);

        metadata.graduated = true;
        emit Graduated(tokenId, parentBalance, characterBalance);
    }

    function _mintAndBurnLiquidityPosition(
        PoolKey memory poolKey,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) private returns (uint256) {
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

        uint256 nextTokenId = POSITION_MANAGER.nextTokenId();

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

        IERC721(address(POSITION_MANAGER)).transferFrom(address(this), address(0xdead), nextTokenId);

        return nextTokenId;
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
            HookMiner.find(address(this), flags, creationCode, constructorArgs);

        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);

        // Deploy using OpenZeppelin Create2
        address deployed = Create2.deploy(0, salt, bytecode);
        require(deployed == hookAddress, "Hook address mismatch");

        return hookAddress;
    }
}
