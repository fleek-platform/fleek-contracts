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
import { BaseUniswapDeployments } from "./lib/BaseUniswapDeployments.sol";

contract SwapFeeHook is BaseHook {
    address public immutable FEE_RECIPIENT_1;
    address public immutable FEE_RECIPIENT_2;
    address public immutable TARGET_TOKEN;

    constructor(address _feeRecipient1, address _feeRecipient2, address _targetToken)
        BaseHook(IPoolManager(BaseUniswapDeployments.POOL_MANAGER))
    {
        FEE_RECIPIENT_1 = _feeRecipient1;
        FEE_RECIPIENT_2 = _feeRecipient2;
        TARGET_TOKEN = _targetToken;
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

        if (!targetIsToken0 && Currency.unwrap(key.currency1) != TARGET_TOKEN) {
            return (this.afterSwap.selector, 0);
        }

        int128 targetDelta = targetIsToken0 ? delta.amount0() : delta.amount1();

        if (targetDelta == 0) {
            return (this.afterSwap.selector, 0);
        }

        Currency feeCurrency = targetIsToken0 ? key.currency0 : key.currency1;

        int128 feePerRecipient = targetDelta / 100;

        if (feePerRecipient < 0) {
            feePerRecipient = -feePerRecipient;
        }

        poolManager.take(feeCurrency, FEE_RECIPIENT_1, SafeCast.toUint128(feePerRecipient));
        poolManager.take(feeCurrency, FEE_RECIPIENT_2, SafeCast.toUint128(feePerRecipient));

        int128 totalFee = feePerRecipient * 2;
        int128 hookDelta = targetDelta > 0 ? totalFee : -totalFee;

        return (this.afterSwap.selector, hookDelta);
    }
}
