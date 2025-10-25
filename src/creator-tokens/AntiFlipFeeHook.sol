// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BaseHook } from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseUniswapDeployments } from "./lib/BaseUniswapDeployments.sol";
import { FactoryConfig } from "./lib/FactoryConfig.sol";

/**
 * @title AntiFlipFeeHook
 * @author Fleek
 * @notice Uniswap V4 hook implementing anti-sniper tax on creator token pairs
 *
 * Fee Structure
 * =============
 * Base Fee: 2% on all swaps (always applied to FLK)
 * Snipe Penalty: Additional 10% on sells within personalized time window
 * Maximum Total: 12% (base + penalty)
 *
 * Total Fees by Transaction Type:
 *   Buys: 2% of FLK spent
 *   Sells (after window expires): 2% of FLK received
 *   Sells (within window): 12% of FLK received
 *
 * Fee Distribution
 * ================
 * All swaps: Dynamic split based on creator's token holdings
 *   Creator holds ≥250k: Foundation 75%, Creator 25%
 *   Creator holds ≥150k: Foundation 80%, Creator 20%
 *   Creator holds ≥50k: Foundation 85%, Creator 15%
 *   Creator holds <50k: Foundation 87.5%, Creator 12.5%
 *
 * Anti-Snipe Mechanism
 * ====================
 * Hook is deployed at graduation and only tracks post-graduation LP swaps.
 * Window duration: 30-120 seconds, deterministic per user but unpredictable until buy executes.
 * Entropy: keccak256(user, token, buyTimestamp, graduationTimestamp)
 * Window resets on every subsequent buy, preventing "buy once flip forever" strategies.
 * Buy timestamps automatically recorded in afterSwap() hook.
 */
contract AntiFlipFeeHook is BaseHook {
    /**
     * @notice Address receiving creator's share of fees
     */
    address public immutable CREATOR;

    /**
     * @notice Creator token address (trading pair)
     */
    address public immutable CREATOR_TOKEN;

    /**
     * @notice Vesting wallet address (holds creator's locked tokens)
     */
    address public immutable VESTING_WALLET;

    /**
     * @notice Standard base fee in basis points (2% - always applied)
     */
    uint256 public constant BASE_FEE_BPS = 200;

    /**
     * @notice Anti-snipe penalty fee in basis points (10% - additional on top of base)
     */
    uint256 public constant SNIPE_PENALTY_BPS = 1000;

    /**
     * @notice Maximum total fee in basis points (12% - base + penalty)
     */
    uint256 public constant MAX_TOTAL_FEE_BPS = 1200;

    /**
     * @notice Minimum penalty window duration in seconds
     */
    uint256 public constant MIN_WINDOW = 30;

    /**
     * @notice Range for random window duration (30-120 seconds)
     */
    uint256 public constant WINDOW_RANGE = 91;

    /**
     * @notice Timestamp when token graduated to Uniswap (used for entropy)
     */
    uint256 public graduationTimestamp;

    /**
     * @notice Timestamp of most recent buy for each user
     * @dev Resets on every buy, used to enforce anti-snipe penalty window
     */
    mapping(address => uint256) public userLastBuy;

    /**
     * @notice Constructs the AntiFlipFeeHook
     * @param _creator Address to receive creator's share of fees
     * @param _creatorToken Address of creator token (trading pair)
     * @param _vestingWallet Address holding creator's vesting tokens
     */
    constructor(address _creator, address _creatorToken, address _vestingWallet)
        BaseHook(IPoolManager(BaseUniswapDeployments.POOL_MANAGER))
    {
        CREATOR = _creator;
        CREATOR_TOKEN = _creatorToken;
        VESTING_WALLET = _vestingWallet;
        graduationTimestamp = block.timestamp;
    }

    /**
     * @notice Returns the hook's permission configuration
     * @return Permissions struct indicating this hook uses afterSwap with delta modification
     */
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
     * @notice Calculate personalized penalty window duration for a user
     * @dev Uses deterministic pseudo-randomness based on wallet address and timestamps.
     *      Result is consistent per wallet per buy but unpredictable until on-chain interaction.
     * @param user Address of the user
     * @param buyTimestamp Timestamp of the buy transaction
     * @return Window duration in seconds (30-120)
     */
    function calculateWindow(address user, uint256 buyTimestamp) public view returns (uint256) {
        uint256 seed = uint256(
            keccak256(abi.encodePacked(user, CREATOR_TOKEN, buyTimestamp, graduationTimestamp))
        );

        return MIN_WINDOW + (seed % WINDOW_RANGE);
    }

    /**
     * @notice Get the current total fee for a swap (base + potential snipe penalty)
     * @dev Checks if user is within their anti-snipe window.
     *      Base fee (2%) always applies. Snipe penalty (10%) adds on top if within window.
     *      All fees taken from FLK side only.
     * @param user Address executing the swap
     * @param isBuy True if buying CreatorToken with FLK
     * @return feePercent Total fee in basis points (200 = 2%, 1200 = 12%)
     */
    function getTotalFee(address user, bool isBuy) public view returns (uint256 feePercent) {
        // Base fee always applies
        uint256 totalFee = BASE_FEE_BPS;

        // Additional snipe penalty only on sells
        if (!isBuy) {
            uint256 lastBuyTime = userLastBuy[user];

            if (lastBuyTime > 0) {
                uint256 windowDuration = calculateWindow(user, lastBuyTime);
                uint256 elapsed = block.timestamp - lastBuyTime;

                if (elapsed < windowDuration) {
                    totalFee += SNIPE_PENALTY_BPS;
                }
            }
        }

        return totalFee;
    }

    /**
     * @notice Hook called after every swap in the pool
     * @dev Records buys for anti-snipe tracking, calculates and takes fees.
     *      All fees collected in FLK regardless of swap direction.
     * @param sender Address initiating the swap
     * @param key Pool key identifying the pool
     * @param delta Balance changes from the swap
     * @return selector Function selector for continued execution
     * @return hookDelta Fee amount to be taken from swap proceeds (positive for sells, negative for buys)
     */
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        bool flkIsToken0 = Currency.unwrap(key.currency0) == FactoryConfig.FLK;
        int128 flkDelta = flkIsToken0 ? delta.amount0() : delta.amount1();

        if (flkDelta == 0) {
            return (this.afterSwap.selector, 0);
        }

        // Determine if buy or sell
        // If FLK is going out of pool (negative), user is buying CreatorToken
        // If FLK is coming into pool (positive), user is selling CreatorToken
        bool isBuy = flkDelta < 0;

        if (isBuy) {
            userLastBuy[sender] = block.timestamp;
        }

        return _calculateAndTakeFees(sender, key, flkDelta, isBuy, flkIsToken0);
    }

    /**
     * @notice Calculate fees and distribute to foundation and creator
     * @dev Internal helper to reduce stack depth in afterSwap.
     *      All fees taken from FLK side only (never from CreatorToken).
     * @param sender Address being charged fees
     * @param key Pool key for currency identification
     * @param flkDelta FLK balance change from swap
     * @param isBuy True if buying CreatorToken with FLK
     * @param flkIsToken0 True if FLK is token0 in the pool
     * @return selector Function selector for continued execution
     * @return hookDelta Fee amount taken from FLK proceeds
     */
    function _calculateAndTakeFees(
        address sender,
        PoolKey calldata key,
        int128 flkDelta,
        bool isBuy,
        bool flkIsToken0
    ) internal returns (bytes4, int128) {
        uint256 absFlkDelta = flkDelta < 0
            ? uint256(SafeCast.toUint128(-flkDelta))
            : uint256(SafeCast.toUint128(flkDelta));

        uint256 totalFeeBps = getTotalFee(sender, isBuy);

        uint256 totalFee = (absFlkDelta * totalFeeBps) / 10000;

        (uint256 foundationBps, uint256 creatorBps) = _getFeeRates();
        uint256 foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
        uint256 creatorFee = totalFee - foundationFee;

        // Take fees from FLK currency only
        Currency flkCurrency = flkIsToken0 ? key.currency0 : key.currency1;
        poolManager.take(flkCurrency, FactoryConfig.FOUNDATION, SafeCast.toUint128(foundationFee));
        poolManager.take(flkCurrency, CREATOR, SafeCast.toUint128(creatorFee));

        // Return hook delta (taken from FLK side)
        int128 hookDelta = flkDelta > 0
            ? SafeCast.toInt128(SafeCast.toInt256(totalFee))
            : -SafeCast.toInt128(SafeCast.toInt256(totalFee));

        return (this.afterSwap.selector, hookDelta);
    }

    /**
     * @notice Get fee split rates based on creator's token holdings
     * @dev Fee distribution becomes more favorable to foundation as creator holds fewer tokens.
     *      Incentivizes creators to maintain skin in the game.
     * @return foundationBps Foundation's share in basis points
     * @return creatorBps Creator's share in basis points
     */
    function _getFeeRates() internal view returns (uint256 foundationBps, uint256 creatorBps) {
        uint256 creatorBalance = IERC20(CREATOR_TOKEN).balanceOf(CREATOR);
        uint256 vestingBalance = IERC20(CREATOR_TOKEN).balanceOf(VESTING_WALLET);
        uint256 totalHeld = creatorBalance + vestingBalance;

        if (totalHeld >= 250_000e18) return (150, 50);
        if (totalHeld >= 150_000e18) return (160, 40);
        if (totalHeld >= 50_000e18) return (170, 30);
        return (175, 25);
    }
}
