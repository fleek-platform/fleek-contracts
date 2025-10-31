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
    address constant CREATOR_TOKEN = 0x1aC4381a7fB097DE351f492B9468C433e455aE74;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant HOOK = 0xA179D196186681bE0952E7214c386439aFCe0044;
    address constant FOUNDATION = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address constant ACTUAL_USER = 0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9;

    IERC20 token0 = IERC20(FLK_TOKEN < CREATOR_TOKEN ? FLK_TOKEN : CREATOR_TOKEN);
    IERC20 token1 = IERC20(FLK_TOKEN < CREATOR_TOKEN ? CREATOR_TOKEN : FLK_TOKEN);

    function run() external {
        console.log("=== FLK Fee Collection Test ===");
        console.log("Testing with 5,000 FLK swap (2% fee = 100 FLK expected)");
        console.log("");

        vm.startBroadcast();

        PoolSwapTest swapRouter =
            new PoolSwapTest(IPoolManager(BaseUniswapDeployments.POOL_MANAGER()));
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        _logBalancesBefore();

        swapRouter.swap(
            PoolKey({
                currency0: Currency.wrap(address(token0)),
                currency1: Currency.wrap(address(token1)),
                fee: 0,
                tickSpacing: 200,
                hooks: IHooks(HOOK)
            }),
            SwapParams({
                zeroForOne: address(token0) == FLK_TOKEN,
                amountSpecified: -5000000000000000000000,  // 5,000 FLK
                sqrtPriceLimitX96: address(token0) == FLK_TOKEN
                    ? 4295128740
                    : 1461446703485210103287273052203988822378723970341
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            abi.encodePacked(ACTUAL_USER)
        );

        _logBalancesAfter();

        vm.stopBroadcast();
    }

    function _logBalancesBefore() internal view {
        console.log("BEFORE:");
        console.log("  User FLK:", IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER) / 1e18);

        (bool s1, bytes memory d1) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", FOUNDATION));
        console.log("  Foundation Claimable:", (s1 ? abi.decode(d1, (uint256)) : 0) / 1e18, "FLK");
        console.log("");
    }

    function _logBalancesAfter() internal view {
        console.log("AFTER:");
        console.log("  User FLK:", IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER) / 1e18);

        (bool s1, bytes memory d1) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", FOUNDATION));
        (bool s2, bytes memory d2) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", ACTUAL_USER));
        console.log("  Foundation Claimable:", (s1 ? abi.decode(d1, (uint256)) : 0) / 1e18, "FLK");
        console.log("  Creator Claimable:", (s2 ? abi.decode(d2, (uint256)) : 0) / 1e18, "FLK");
        console.log("");
        console.log("SUCCESS!");
    }
}
