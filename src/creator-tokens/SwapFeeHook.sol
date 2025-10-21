// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BaseHook } from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";

contract SwapFeeHook is BaseHook {
    address public immutable feeRecipient;

    constructor(IPoolManager _poolManager, address _feeRecipient) BaseHook(_poolManager) {
        feeRecipient = _feeRecipient;
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
        // TODO: Update with mainnet address
        address targetToken = 0x88DB73F86c7025608420f447ae003b7CD3286E71;

        bool targetIsToken0 = Currency.unwrap(key.currency0) == targetToken;

        if (!targetIsToken0 && Currency.unwrap(key.currency1) != targetToken) {
            return (this.afterSwap.selector, 0);
        }

        int128 targetDelta;
        Currency feeCurrency;

        if (targetIsToken0) {
            targetDelta = delta.amount0();
            feeCurrency = key.currency0;
        } else {
            targetDelta = delta.amount1();
            feeCurrency = key.currency1;
        }

        int128 feeAmount = targetDelta / 50; // 2% of actual target token flow

        if (feeAmount < 0) {
            feeAmount = -feeAmount;
        }

        poolManager.take(feeCurrency, feeRecipient, uint128(feeAmount));

        return (this.afterSwap.selector, 0);
    }
}
