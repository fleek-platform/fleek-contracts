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

contract SwapFeeHook is BaseHook {
    address public immutable FOUNDATION;
    address public immutable CREATOR;
    address public immutable TARGET_TOKEN;
    address public immutable CHARACTER_TOKEN;
    address public immutable VESTING_WALLET;

    constructor(
        address _foundation,
        address _creator,
        address _targetToken,
        address _characterToken,
        address _vestingWallet
    ) BaseHook(IPoolManager(BaseUniswapDeployments.POOL_MANAGER)) {
        FOUNDATION = _foundation;
        CREATOR = _creator;
        TARGET_TOKEN = _targetToken;
        CHARACTER_TOKEN = _characterToken;
        VESTING_WALLET = _vestingWallet;
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

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        bool targetIsToken0 = Currency.unwrap(key.currency0) == TARGET_TOKEN;
        int128 targetDelta = targetIsToken0 ? delta.amount0() : delta.amount1();

        if (targetDelta == 0) {
            return (this.afterSwap.selector, 0);
        }

        Currency feeCurrency = targetIsToken0 ? key.currency0 : key.currency1;

        uint256 absDelta;
        if (targetDelta < 0) {
            absDelta = uint256(SafeCast.toUint128(-targetDelta));
        } else {
            absDelta = uint256(SafeCast.toUint128(targetDelta));
        }

        (uint256 foundationBps, uint256 creatorBps) = _getFeeRates();

        uint256 foundationFee = (absDelta * foundationBps) / 10000;
        uint256 creatorFee = (absDelta * creatorBps) / 10000;

        poolManager.take(feeCurrency, FOUNDATION, SafeCast.toUint128(foundationFee));
        poolManager.take(feeCurrency, CREATOR, SafeCast.toUint128(creatorFee));

        uint256 totalFee = foundationFee + creatorFee;
        int128 hookDelta;
        if (targetDelta > 0) {
            hookDelta = SafeCast.toInt128(SafeCast.toInt256(totalFee));
        } else {
            hookDelta = -SafeCast.toInt128(SafeCast.toInt256(totalFee));
        }

        return (this.afterSwap.selector, hookDelta);
    }

    function _getFeeRates() internal view returns (uint256 foundationBps, uint256 creatorBps) {
        uint256 creatorBalance = IERC20(CHARACTER_TOKEN).balanceOf(CREATOR);
        uint256 vestingBalance = IERC20(CHARACTER_TOKEN).balanceOf(VESTING_WALLET);
        uint256 totalHeld = creatorBalance + vestingBalance;

        if (totalHeld >= 250_000e18) return (150, 50);
        if (totalHeld >= 150_000e18) return (160, 40);
        if (totalHeld >= 50_000e18) return (170, 30);
        return (175, 25);
    }
}
