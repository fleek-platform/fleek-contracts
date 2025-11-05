// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/erc20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { Actions } from "v4-periphery/src/libraries/Actions.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { LiquidityAmounts } from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import { UniversalAntiFlipFeeHook } from "../hooks/UniversalAntiFlipFeeHook.sol";
import { CreatorCoin } from "../tokens/CreatorCoin.sol";
import { BaseUniswapDeployments } from "../libraries/BaseUniswapDeployments.sol";
import { Config } from "../libraries/Config.sol";
import { LinearCurveMathV4 } from "../libraries/LinearCurveMath.sol";
import { AntiFlipFeeLib } from "../libraries/AntiFlipFeeLib.sol";

/**
 * @title BondingCurve
 * @notice Linear bonding curve for creator tokens that graduates to Uniswap V4
 * @dev Sells tokens via linear curve until threshold, then creates permanent LP
 */
contract BondingCurve {
    /**
     * @notice Core bonding curve configuration and state
     * @param creator Creator address for fee distribution
     * @param creatorToken Creator token address
     * @param slope Linear curve slope parameter
     * @param vestingWallet Vesting wallet for anti-flip fee exemption
     * @param universalHook Universal hook address for graduated pool
     * @param deploymentTimestamp Contract deployment time for fee calculations
     * @param graduated Whether curve has graduated to Uniswap
     */
    struct BondingMetadata {
        address creator;
        address creatorToken;
        uint256 slope;
        address vestingWallet;
        address universalHook;
        uint256 deploymentTimestamp;
        bool graduated;
    }

    /**
     * @notice Uniswap V4 pool manager
     */
    IPoolManager public immutable POOL_MANAGER;

    /**
     * @notice Uniswap V4 position manager
     */
    IPositionManager public immutable POSITION_MANAGER;

    /**
     * @notice Pool swap fee (0%)
     */
    uint24 public constant POOL_FEE = 0;

    /**
     * @notice Pool tick spacing
     */
    int24 public constant TICK_SPACING = 200;

    /**
     * @notice Minimum purchase amount in FLK
     */
    uint64 public constant MIN_PURCHASE_FLK = 1e17;

    /**
     * @notice Bonding curve metadata
     */
    BondingMetadata public metadata;

    /**
     * @notice Total creator tokens sold on the curve
     */
    uint256 public creatorTokensSold;

    /**
     * @notice Tracks last buy timestamp per user for anti-flip fees
     */
    mapping(address => uint256) public userLastBuy;

    /**
     * @dev Prevents double initialization
     */
    bool private _initialized;

    /**
     * @notice Emitted when user buys tokens
     */
    event Buy(address indexed user, uint256 parentIn, uint256 creatorOut, uint256 fee);

    /**
     * @notice Emitted when user sells tokens
     */
    event Sell(address indexed user, uint256 creatorIn, uint256 parentOut, uint256 fee);

    /**
     * @notice Emitted when curve graduates to Uniswap
     */
    event Graduated(uint256 tokenId, uint256 parentTokenBalance, uint256 creatorTokenBalance);

    /**
     * @notice Emitted when fees are collected
     */
    event FeesCollected(
        address indexed foundation,
        address indexed creator,
        uint256 foundationAmount,
        uint256 creatorAmount
    );

    /**
     * @notice Thrown when attempting to trade after graduation
     */
    error AlreadyGraduated();

    /**
     * @notice Thrown when attempting to initialize twice
     */
    error AlreadyInitialized();

    /**
     * @notice Thrown when input amount is zero
     */
    error ZeroInput();

    /**
     * @notice Thrown when slippage tolerance exceeded
     */
    error SlippageExceeded();

    /**
     * @notice Thrown when purchase amount below minimum
     */
    error NotEnoughFLK();

    /**
     * @notice Thrown when token transfer fails
     */
    error TokenTransferFailed();

    /**
     * @notice Thrown when starting price is invalid
     */
    error InvalidStartingPrice();

    constructor() {
        POOL_MANAGER = IPoolManager(BaseUniswapDeployments.POOL_MANAGER());
        POSITION_MANAGER = IPositionManager(payable(BaseUniswapDeployments.POSITION_MANAGER()));
    }

    /**
     * @notice Initializes bonding curve parameters
     * @param _creator Creator address for fee distribution
     * @param _creatorToken Creator token address
     * @param _graduationThreshold FLK amount at which curve graduates
     * @param _basePrice Initial token price
     * @param _creatorSupply Total token supply
     * @param _vestingWallet Vesting wallet address
     * @param _universalHook Universal hook address
     */
    function initialize(
        address _creator,
        address _creatorToken,
        uint256 _graduationThreshold,
        uint256 _basePrice,
        uint256 _creatorSupply,
        address _vestingWallet,
        address _universalHook
    ) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        uint256 finalPrice = LinearCurveMathV4.finalPrice(
            _graduationThreshold,
            _creatorSupply,
            _basePrice,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        uint256 slope = LinearCurveMathV4.slope(
            finalPrice,
            _basePrice,
            _creatorSupply,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        metadata = BondingMetadata({
            creator: _creator,
            creatorToken: _creatorToken,
            slope: slope,
            vestingWallet: _vestingWallet,
            universalHook: _universalHook,
            deploymentTimestamp: block.timestamp,
            graduated: false
        });
    }

    /**
     * @notice Buy creator tokens with parent tokens
     * @param parentAmountIn Amount of parent tokens to spend on the curve (fees added on top)
     * @param minCreatorOut Minimum creator tokens to receive
     */
    function buy(uint256 parentAmountIn, uint256 minCreatorOut) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (parentAmountIn < MIN_PURCHASE_FLK) revert NotEnoughFLK();

        uint256 creatorOut = LinearCurveMathV4.calculateBuyAmount(
            parentAmountIn,
            creatorTokensSold,
            Config.BASE_PRICE,
            metadata.slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        // Cap to maximum sellable supply (not total balance, which includes LP reserve)
        uint256 maxAvailable = (Config.BONDING_CURVE_ALLOCATION / 2) - creatorTokensSold;

        uint256 curveCost = parentAmountIn;
        if (creatorOut > maxAvailable) {
            creatorOut = maxAvailable;
            curveCost = LinearCurveMathV4.calculateBuyCost(
                creatorOut,
                creatorTokensSold,
                Config.BASE_PRICE,
                metadata.slope,
                Config.CREATOR_COIN_DECIMALS,
                Config.FLK_DECIMALS
            );
        }

        if (creatorOut < minCreatorOut) revert SlippageExceeded();

        address effectiveOrigin = AntiFlipFeeLib.getEffectiveOrigin(msg.sender, tx.origin);

        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = AntiFlipFeeLib.calculateFees(
            curveCost,
            effectiveOrigin,
            true,
            userLastBuy,
            metadata.creator,
            metadata.creatorToken,
            metadata.vestingWallet,
            block.prevrandao,
            metadata.deploymentTimestamp
        );

        uint256 totalCost = curveCost + totalFee;

        creatorTokensSold += creatorOut;

        require(
            IERC20(Config.FLK()).transferFrom(msg.sender, address(this), curveCost),
            TokenTransferFailed()
        );

        if (totalFee > 0) {
            require(
                IERC20(Config.FLK()).transferFrom(msg.sender, Config.FOUNDATION(), foundationFee),
                TokenTransferFailed()
            );
            require(
                IERC20(Config.FLK()).transferFrom(msg.sender, metadata.creator, creatorFee),
                TokenTransferFailed()
            );
            emit FeesCollected(Config.FOUNDATION(), metadata.creator, foundationFee, creatorFee);
        }

        require(
            IERC20(metadata.creatorToken).transfer(msg.sender, creatorOut), TokenTransferFailed()
        );

        userLastBuy[effectiveOrigin] = block.timestamp;

        uint256 windowDuration = AntiFlipFeeLib.calculateWindow(
            effectiveOrigin,
            metadata.creatorToken,
            block.timestamp,
            block.prevrandao,
            metadata.deploymentTimestamp
        );

        CreatorCoin(metadata.creatorToken)
            .lockTransfers(effectiveOrigin, block.timestamp + windowDuration);

        emit Buy(msg.sender, totalCost, creatorOut, totalFee);

        if (creatorTokensSold >= (Config.BONDING_CURVE_ALLOCATION / 2)) {
            _graduate();
        }
    }

    /**
     * @notice Buy exact amount of creator tokens
     * @param creatorAmountOut Exact amount of creator tokens to receive
     * @param maxParentIn Maximum parent tokens willing to spend (including fees)
     */
    function buyExactTokens(uint256 creatorAmountOut, uint256 maxParentIn) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (creatorAmountOut == 0) revert ZeroInput();

        uint256 maxAvailable = (Config.BONDING_CURVE_ALLOCATION / 2) - creatorTokensSold;
        if (creatorAmountOut > maxAvailable) revert SlippageExceeded();

        uint256 curveCost = LinearCurveMathV4.calculateBuyCost(
            creatorAmountOut,
            creatorTokensSold,
            Config.BASE_PRICE,
            metadata.slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        address effectiveOrigin = AntiFlipFeeLib.getEffectiveOrigin(msg.sender, tx.origin);

        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = AntiFlipFeeLib.calculateFees(
            curveCost,
            effectiveOrigin,
            true,
            userLastBuy,
            metadata.creator,
            metadata.creatorToken,
            metadata.vestingWallet,
            block.prevrandao,
            metadata.deploymentTimestamp
        );

        uint256 totalCost = curveCost + totalFee;

        if (totalCost > maxParentIn) revert SlippageExceeded();

        creatorTokensSold += creatorAmountOut;

        require(
            IERC20(Config.FLK()).transferFrom(msg.sender, address(this), curveCost),
            TokenTransferFailed()
        );

        if (totalFee > 0) {
            require(
                IERC20(Config.FLK()).transferFrom(msg.sender, Config.FOUNDATION(), foundationFee),
                TokenTransferFailed()
            );
            require(
                IERC20(Config.FLK()).transferFrom(msg.sender, metadata.creator, creatorFee),
                TokenTransferFailed()
            );
            emit FeesCollected(Config.FOUNDATION(), metadata.creator, foundationFee, creatorFee);
        }

        require(
            IERC20(metadata.creatorToken).transfer(msg.sender, creatorAmountOut),
            TokenTransferFailed()
        );

        uint256 windowDuration = AntiFlipFeeLib.calculateWindow(
            effectiveOrigin,
            metadata.creatorToken,
            block.timestamp,
            block.prevrandao,
            metadata.deploymentTimestamp
        );

        userLastBuy[effectiveOrigin] = block.timestamp;

        CreatorCoin(metadata.creatorToken)
            .lockTransfers(effectiveOrigin, block.timestamp + windowDuration);

        emit Buy(msg.sender, totalCost, creatorAmountOut, totalFee);

        if (creatorTokensSold >= (Config.BONDING_CURVE_ALLOCATION / 2)) {
            _graduate();
        }
    }

    /**
     * @notice Sell creator tokens for parent tokens
     * @param creatorAmountIn Amount of creator tokens to sell
     * @param minParentOut Minimum parent tokens to receive
     */
    function sell(uint256 creatorAmountIn, uint256 minParentOut) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (creatorAmountIn < MIN_PURCHASE_FLK) revert ZeroInput();

        uint256 parentOut = LinearCurveMathV4.calculateSellAmount(
            creatorAmountIn,
            creatorTokensSold,
            Config.BASE_PRICE,
            metadata.slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        uint256 available = IERC20(Config.FLK()).balanceOf(address(this));
        if (parentOut > available) {
            parentOut = available;
            creatorAmountIn = LinearCurveMathV4.calculateSellCost(
                parentOut,
                creatorTokensSold,
                Config.BASE_PRICE,
                metadata.slope,
                Config.CREATOR_COIN_DECIMALS,
                Config.FLK_DECIMALS
            );
        }

        if (parentOut < minParentOut) revert SlippageExceeded();

        creatorTokensSold -= creatorAmountIn;

        require(
            IERC20(metadata.creatorToken).transferFrom(msg.sender, address(this), creatorAmountIn),
            TokenTransferFailed()
        );

        address effectiveOrigin = AntiFlipFeeLib.getEffectiveOrigin(msg.sender, tx.origin);

        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = AntiFlipFeeLib.calculateFees(
            parentOut,
            effectiveOrigin,
            false,
            userLastBuy,
            metadata.creator,
            metadata.creatorToken,
            metadata.vestingWallet,
            block.prevrandao,
            metadata.deploymentTimestamp
        );

        uint256 netParentOut = parentOut - totalFee;

        require(IERC20(Config.FLK()).transfer(msg.sender, netParentOut), TokenTransferFailed());

        if (totalFee > 0) {
            require(
                IERC20(Config.FLK()).transfer(Config.FOUNDATION(), foundationFee),
                TokenTransferFailed()
            );
            require(
                IERC20(Config.FLK()).transfer(metadata.creator, creatorFee), TokenTransferFailed()
            );
            emit FeesCollected(Config.FOUNDATION(), metadata.creator, foundationFee, creatorFee);
        }

        emit Sell(msg.sender, creatorAmountIn, parentOut, totalFee);
    }

    /**
     * @notice Sell creator tokens to receive exact amount of parent tokens
     * @param parentAmountOut Exact amount of parent tokens to receive (before fees)
     * @param maxCreatorIn Maximum creator tokens willing to sell
     */
    function sellExactTokens(uint256 parentAmountOut, uint256 maxCreatorIn) external {
        if (metadata.graduated) revert AlreadyGraduated();
        if (parentAmountOut == 0) revert ZeroInput();

        uint256 available = IERC20(Config.FLK()).balanceOf(address(this));
        if (parentAmountOut > available) revert SlippageExceeded();

        uint256 creatorAmountIn = LinearCurveMathV4.calculateSellCost(
            parentAmountOut,
            creatorTokensSold,
            Config.BASE_PRICE,
            metadata.slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        if (creatorAmountIn > maxCreatorIn) revert SlippageExceeded();

        creatorTokensSold -= creatorAmountIn;

        require(
            IERC20(metadata.creatorToken).transferFrom(msg.sender, address(this), creatorAmountIn),
            TokenTransferFailed()
        );

        address effectiveOrigin = AntiFlipFeeLib.getEffectiveOrigin(msg.sender, tx.origin);

        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = AntiFlipFeeLib.calculateFees(
            parentAmountOut,
            effectiveOrigin,
            false,
            userLastBuy,
            metadata.creator,
            metadata.creatorToken,
            metadata.vestingWallet,
            block.prevrandao,
            metadata.deploymentTimestamp
        );

        uint256 netParentOut = parentAmountOut - totalFee;

        require(IERC20(Config.FLK()).transfer(msg.sender, netParentOut), TokenTransferFailed());

        if (totalFee > 0) {
            require(
                IERC20(Config.FLK()).transfer(Config.FOUNDATION(), foundationFee),
                TokenTransferFailed()
            );
            require(
                IERC20(Config.FLK()).transfer(metadata.creator, creatorFee), TokenTransferFailed()
            );
            emit FeesCollected(Config.FOUNDATION(), metadata.creator, foundationFee, creatorFee);
        }

        emit Sell(msg.sender, creatorAmountIn, parentAmountOut, totalFee);
    }

    /**
     * @notice Graduates the bonding curve to Uniswap V4 with full-range liquidity
     * @dev Creates a single full-range liquidity position from MIN_TICK to MAX_TICK.
     *
     *      At graduation with ~225k CreatorTokens and ~20,675 FLK, all tokens are deposited
     *      into a single LP position providing liquidity across the entire price range.
     *
     *      The pool uses 0% swap fee, but the hook takes 2% in FLK only on each swap.
     *      The LP NFT is burned to 0xdead, permanently locking the liquidity.
     */
    function _graduate() internal {
        uint256 parentBalance = IERC20(Config.FLK()).balanceOf(address(this));
        uint256 creatorBalance = IERC20(metadata.creatorToken).balanceOf(address(this));

        // Sort tokens and amounts, calculate price from actual balances
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint160 startingPrice;

        if (Config.FLK() < metadata.creatorToken) {
            // token0=parent, token1=creator
            // sqrtPriceX96 = sqrt(creator/parent) * 2^96
            token0 = Config.FLK();
            token1 = metadata.creatorToken;
            amount0 = parentBalance;
            amount1 = creatorBalance;

            uint256 creatorInParentDecimals = LinearCurveMathV4.convertPrice(
                creatorBalance, Config.CREATOR_COIN_DECIMALS, Config.FLK_DECIMALS
            );

            uint256 sqrtCreator = Math.sqrt(creatorInParentDecimals);
            uint256 sqrtParent = Math.sqrt(parentBalance);
            startingPrice = SafeCast.toUint160((sqrtCreator << 96) / sqrtParent);
        } else {
            // token0=creator, token1=parent
            // sqrtPriceX96 = sqrt(parent/creator) * 2^96
            token0 = metadata.creatorToken;
            token1 = Config.FLK();
            amount0 = creatorBalance;
            amount1 = parentBalance;

            uint256 parentInCreatorDecimals = LinearCurveMathV4.convertPrice(
                parentBalance, Config.FLK_DECIMALS, Config.CREATOR_COIN_DECIMALS
            );

            uint256 sqrtParent = Math.sqrt(parentInCreatorDecimals);
            uint256 sqrtCreator = Math.sqrt(creatorBalance);

            startingPrice = SafeCast.toUint160((sqrtParent << 96) / sqrtCreator);
        }

        require(
            startingPrice >= TickMath.MIN_SQRT_PRICE && startingPrice <= TickMath.MAX_SQRT_PRICE,
            InvalidStartingPrice()
        );

        UniversalAntiFlipFeeHook(metadata.universalHook)
            .registerToken(metadata.creatorToken, metadata.creator, metadata.vestingWallet);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(metadata.universalHook)
        });

        POOL_MANAGER.initialize(poolKey, startingPrice);

        uint256 tokenId =
            _mintAndBurnLiquidityPosition(poolKey, token0, token1, amount0, amount1, startingPrice);

        metadata.graduated = true;
        emit Graduated(tokenId, parentBalance, creatorBalance);
    }

    /**
     * @notice Creates full-range LP position and burns NFT to lock liquidity
     * @param poolKey Uniswap V4 pool configuration
     * @param token0 First token address (lower sorted)
     * @param token1 Second token address (higher sorted)
     * @param amount0 Amount of token0 to provide
     * @param amount1 Amount of token1 to provide
     * @param sqrtPriceX96 Initial pool price in sqrt format
     * @return tokenId ID of the burned LP NFT
     */
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

        _approveTokensForPosition(token0, token1);

        uint256 nextTokenId = POSITION_MANAGER.nextTokenId();

        _executePositionMint(poolKey, tickLower, tickUpper, liquidity, amount0, amount1);

        IERC721(address(POSITION_MANAGER)).transferFrom(address(this), address(0xdead), nextTokenId);

        return nextTokenId;
    }

    /**
     * @notice Approves tokens for Uniswap position manager via Permit2
     * @param token0 First token to approve
     * @param token1 Second token to approve
     */
    function _approveTokensForPosition(address token0, address token1) private {
        IERC20(token0).approve(BaseUniswapDeployments.PERMIT2, type(uint256).max);
        IERC20(token1).approve(BaseUniswapDeployments.PERMIT2, type(uint256).max);

        uint48 expiration = type(uint48).max;
        IAllowanceTransfer(BaseUniswapDeployments.PERMIT2)
            .approve(token0, address(POSITION_MANAGER), type(uint160).max, expiration);
        IAllowanceTransfer(BaseUniswapDeployments.PERMIT2)
            .approve(token1, address(POSITION_MANAGER), type(uint160).max, expiration);
    }

    /**
     * @notice Executes LP minting through position manager
     * @param poolKey Pool configuration
     * @param tickLower Lower tick bound for position
     * @param tickUpper Upper tick bound for position
     * @param liquidity Liquidity amount to mint
     * @param amount0 Token0 amount for position
     * @param amount1 Token1 amount for position
     */
    function _executePositionMint(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1
    ) private {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR)
        );
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
}
