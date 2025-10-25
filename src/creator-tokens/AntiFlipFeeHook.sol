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
import { AntiFlipFeeLib } from "./lib/AntiFlipFeeLib.sol";
import { BaseUniswapDeployments } from "./lib/BaseUniswapDeployments.sol";
import { FactoryConfig } from "./lib/FactoryConfig.sol";

/**
 * @title AntiFlipFeeHook
 * @author Fleek
 * @notice Uniswap V4 hook implementing anti-sniper tax on creator token pairs
 *
 * Total Fees by Transaction Type:
 *   Buys: 2% of FLK spent
 *   Sells (after window expires): 2% of FLK received
 *   Sells (within window): 12% of FLK received
 *
 * Implementation Notes
 * ====================
 * Hook is deployed at graduation and only tracks post-graduation LP swaps.
 * Uses graduationTimestamp for entropy in window calculation.
 * Buy timestamps automatically recorded in afterSwap() hook.
 *
 * See AntiFlipFeeLib for complete fee structure and anti-snipe mechanism documentation.
 */
contract AntiFlipFeeHook is BaseHook {
    address public immutable CREATOR;
    address public immutable CREATOR_TOKEN;
    address public immutable VESTING_WALLET;
    uint256 public immutable graduationTimestamp;

    mapping(address => uint256) public userLastBuy;

    constructor(address _creator, address _creatorToken, address _vestingWallet)
        BaseHook(IPoolManager(BaseUniswapDeployments.POOL_MANAGER))
    {
        CREATOR = _creator;
        CREATOR_TOKEN = _creatorToken;
        VESTING_WALLET = _vestingWallet;
        graduationTimestamp = block.timestamp;
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

        (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) = AntiFlipFeeLib.calculateFees(
            absFlkDelta,
            sender,
            isBuy,
            userLastBuy,
            CREATOR,
            CREATOR_TOKEN,
            VESTING_WALLET,
            graduationTimestamp
        );

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
}
