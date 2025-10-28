// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { BaseUniswapDeployments } from "../src/creator-tokens/libraries/BaseUniswapDeployments.sol";

contract TestGraduatedPoolSwapV7 is Script {
    address constant CREATOR_TOKEN = 0xAA7a5D3ff533aD5AEb3518a5B00c7d8A6B299927;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant HOOK = 0x71055B16F94533Fa4B717aDa92cA7061d37E40c8;
    address constant FOUNDATION = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;

    IERC20 token0 = IERC20(FLK_TOKEN < CREATOR_TOKEN ? FLK_TOKEN : CREATOR_TOKEN);
    IERC20 token1 = IERC20(FLK_TOKEN < CREATOR_TOKEN ? CREATOR_TOKEN : FLK_TOKEN);

    function run() external {
        console.log("=== FINAL TEST: BeforeSwap with Specified Currency ===");

        vm.startBroadcast();

        PoolSwapTest swapRouter =
            new PoolSwapTest(IPoolManager(BaseUniswapDeployments.POOL_MANAGER()));
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        uint256 flkBefore = IERC20(FLK_TOKEN).balanceOf(msg.sender);
        uint256 foundationFlkBefore = IERC20(FLK_TOKEN).balanceOf(FOUNDATION);

        console.log("Swapper FLK Before:", flkBefore / 1e18);
        console.log("Foundation FLK Before:", foundationFlkBefore / 1e18);

        bool zeroForOne = address(token0) == FLK_TOKEN;

        swapRouter.swap(
            PoolKey({
                currency0: Currency.wrap(address(token0)),
                currency1: Currency.wrap(address(token1)),
                fee: 0,
                tickSpacing: 200,
                hooks: IHooks(HOOK)
            }),
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -100e18,
                sqrtPriceLimitX96: zeroForOne
                    ? 4295128740
                    : 1461446703485210103287273052203988822378723970341
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );

        uint256 flkAfter = IERC20(FLK_TOKEN).balanceOf(msg.sender);
        uint256 foundationFlkAfter = IERC20(FLK_TOKEN).balanceOf(FOUNDATION);

        console.log("Swapper FLK After:", flkAfter / 1e18);
        console.log("Foundation FLK After:", foundationFlkAfter / 1e18);
        console.log("Total FLK Spent:", (flkBefore - flkAfter) / 1e18);
        console.log("Foundation Fee Received:", (foundationFlkAfter - foundationFlkBefore) / 1e18);

        if (foundationFlkAfter > foundationFlkBefore) {
            console.log("SUCCESS!!!");
        }

        vm.stopBroadcast();
    }
}
