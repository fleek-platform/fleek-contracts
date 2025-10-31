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

contract TestGraduatedPoolSell is Script {
    address constant CREATOR_TOKEN = 0x1aC4381a7fB097DE351f492B9468C433e455aE74;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant HOOK = 0xA179D196186681bE0952E7214c386439aFCe0044;
    address constant FOUNDATION = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address constant ACTUAL_USER = 0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9;

    IERC20 token0 = IERC20(FLK_TOKEN < CREATOR_TOKEN ? FLK_TOKEN : CREATOR_TOKEN);
    IERC20 token1 = IERC20(FLK_TOKEN < CREATOR_TOKEN ? CREATOR_TOKEN : FLK_TOKEN);

    function run() external {
        console.log("=== Creator Token SELL Test ===");
        console.log("Testing selling 10,000 creator tokens for FLK");

        // Check anti-flip window status
        _checkAntiFlipStatus();
        console.log("");

        // Store balances before
        uint256[4] memory balancesBefore;
        balancesBefore[0] = IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER);
        balancesBefore[1] = IERC20(CREATOR_TOKEN).balanceOf(ACTUAL_USER);

        // Track fees before
        {
            (bool s1, bytes memory d1) =
                HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", FOUNDATION));
            (bool s2, bytes memory d2) =
                HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", ACTUAL_USER));
            balancesBefore[2] = s1 ? abi.decode(d1, (uint256)) : 0;
            balancesBefore[3] = s2 ? abi.decode(d2, (uint256)) : 0;
        }

        _logBalancesBefore();

        vm.startBroadcast();

        PoolSwapTest swapRouter =
            new PoolSwapTest(IPoolManager(BaseUniswapDeployments.POOL_MANAGER()));
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        // Selling creator tokens for FLK
        swapRouter.swap(
            PoolKey({
                currency0: Currency.wrap(address(token0)),
                currency1: Currency.wrap(address(token1)),
                fee: 0,
                tickSpacing: 200,
                hooks: IHooks(HOOK)
            }),
            SwapParams({
                zeroForOne: address(token0) == CREATOR_TOKEN,
                amountSpecified: -10000000000000000000000, // Selling 10,000 creator tokens
                sqrtPriceLimitX96: address(token0) == CREATOR_TOKEN
                    ? 4295128740
                    : 1461446703485210103287273052203988822378723970341
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            abi.encodePacked(ACTUAL_USER)
        );

        vm.stopBroadcast();

        // Store balances after
        uint256[4] memory balancesAfter;
        balancesAfter[0] = IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER);
        balancesAfter[1] = IERC20(CREATOR_TOKEN).balanceOf(ACTUAL_USER);

        {
            (bool s1, bytes memory d1) =
                HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", FOUNDATION));
            (bool s2, bytes memory d2) =
                HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", ACTUAL_USER));
            balancesAfter[2] = s1 ? abi.decode(d1, (uint256)) : 0;
            balancesAfter[3] = s2 ? abi.decode(d2, (uint256)) : 0;
        }

        _logBalancesAfter();

        // Calculate fee percentage
        _calculateFeePercentage(balancesBefore, balancesAfter);
    }

    function _checkAntiFlipStatus() internal view {
        console.log("=== Anti-Flip Status ===");

        // Get last buy timestamp
        (bool s1, bytes memory d1) = HOOK.staticcall(
            abi.encodeWithSignature("userLastBuy(address,address)", CREATOR_TOKEN, ACTUAL_USER)
        );
        uint256 lastBuyTime = s1 ? abi.decode(d1, (uint256)) : 0;

        // Get graduation timestamp for entropy
        (bool s2, bytes memory d2) = HOOK.staticcall(
            abi.encodeWithSignature("tokenGraduationTimestamp(address)", CREATOR_TOKEN)
        );
        uint256 graduationTimestamp = s2 ? abi.decode(d2, (uint256)) : 0;

        if (lastBuyTime > 0) {
            uint256 timeSinceBuy = block.timestamp - lastBuyTime;

            // Calculate personalized window (30-120 seconds)
            uint256 seed = uint256(
                keccak256(
                    abi.encodePacked(ACTUAL_USER, CREATOR_TOKEN, lastBuyTime, graduationTimestamp)
                )
            );
            uint256 personalWindow = 30 + (seed % 91); // 30-120 seconds

            console.log("  Last buy:", timeSinceBuy, "seconds ago");
            console.log("  Personal anti-flip window:", personalWindow, "seconds");

            if (timeSinceBuy < personalWindow) {
                uint256 remainingTime = personalWindow - timeSinceBuy;
                console.log("  Status: IN ANTI-FLIP WINDOW");
                console.log("  Remaining window:", remainingTime, "seconds");
                console.log("  Expected fee: 12% (10% penalty + 2% base)");
            } else {
                console.log("  Status: OUTSIDE ANTI-FLIP WINDOW");
                console.log("  Window expired:", timeSinceBuy - personalWindow, "seconds ago");
                console.log("  Expected fee: 2% (standard fee)");
            }
        } else {
            console.log("  Status: NO PREVIOUS BUY RECORDED");
            console.log("  Expected fee: 2% (standard fee for sells)");
        }
    }

    function _calculateFeePercentage(uint256[4] memory before, uint256[4] memory afterBalances)
        internal
        pure
    {
        console.log("=== Fee Analysis ===");

        uint256 flkReceived = afterBalances[0] - before[0];
        uint256 foundationFeeDelta = afterBalances[2] - before[2];
        uint256 creatorFeeDelta = afterBalances[3] - before[3];
        uint256 totalFees = foundationFeeDelta + creatorFeeDelta;

        uint256 grossFlkAmount = flkReceived + totalFees;

        console.log("  FLK received (net):", flkReceived / 1e18);
        console.log("  Total fees paid:", totalFees / 1e18);
        console.log("  Gross FLK amount:", grossFlkAmount / 1e18);

        if (grossFlkAmount > 0) {
            uint256 feeBasisPoints = (totalFees * 10000) / grossFlkAmount;
            // Display as basis points for precision
            console.log("  ACTUAL FEE (basis points):", feeBasisPoints);
            // Display as percentage (will show integer percentage)
            console.log("  ACTUAL FEE PERCENTAGE:", feeBasisPoints / 100, "%");
        }

        console.log("  Fee breakdown:");
        console.log("    Foundation:", foundationFeeDelta / 1e18, "FLK");
        console.log("    Creator:", creatorFeeDelta / 1e18, "FLK");
    }

    function _logBalancesBefore() internal view {
        console.log("BEFORE:");
        console.log("  User FLK:", IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER) / 1e18);
        console.log("  User Creator Token:", IERC20(CREATOR_TOKEN).balanceOf(ACTUAL_USER) / 1e18);

        (bool s1, bytes memory d1) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", FOUNDATION));
        (bool s2, bytes memory d2) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", ACTUAL_USER));
        console.log("  Foundation Claimable:", (s1 ? abi.decode(d1, (uint256)) : 0) / 1e18, "FLK");
        console.log("  Creator Claimable:", (s2 ? abi.decode(d2, (uint256)) : 0) / 1e18, "FLK");
        console.log("");
    }

    function _logBalancesAfter() internal view {
        console.log("AFTER:");
        console.log("  User FLK:", IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER) / 1e18);
        console.log("  User Creator Token:", IERC20(CREATOR_TOKEN).balanceOf(ACTUAL_USER) / 1e18);

        (bool s1, bytes memory d1) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", FOUNDATION));
        (bool s2, bytes memory d2) =
            HOOK.staticcall(abi.encodeWithSignature("claimableFees(address)", ACTUAL_USER));
        console.log("  Foundation Claimable:", (s1 ? abi.decode(d1, (uint256)) : 0) / 1e18, "FLK");
        console.log("  Creator Claimable:", (s2 ? abi.decode(d2, (uint256)) : 0) / 1e18, "FLK");
        console.log("");
        console.log("SUCCESS! Sell executed");
    }
}

