// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/curve/BondingCurve.sol";
import { CreatorCoin } from "../src/creator-tokens/tokens/CreatorCoin.sol";
import { Vm } from "forge-std/Vm.sol";

contract TestBondingCurveFees is Script {
    address constant FACTORY = 0xa9E076e0F71d9D4B0B3Ea06f7834B42511562258;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant FOUNDATION = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address constant ACTUAL_USER = 0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9;

    function run() external {
        console.log("=== Bonding Curve Fee Test ===");
        console.log("Testing 2% buy fee and 12% anti-flip sell fee");
        console.log("");

        vm.startBroadcast();

        (address tokenAddress, address bondingCurveAddress) = deployToken();

        CreatorCoin token = CreatorCoin(tokenAddress);
        BondingCurve curve = BondingCurve(bondingCurveAddress);

        uint256 tokensReceived = testBuyFlow(token, curve, bondingCurveAddress);

        checkAndWaitForLockExpiry(token);

        testSellFlow(token, curve, bondingCurveAddress, tokensReceived);

        vm.stopBroadcast();
    }

    function deployToken() internal returns (address tokenAddress, address bondingCurveAddress) {
        console.log("Step 1: Deploying fresh creator token...");
        vm.recordLogs();
        CreatorTokenFactory(FACTORY)
            .deployNew(ACTUAL_USER, "FeeTest", "FTEST", uint64(block.timestamp));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (tokenAddress, bondingCurveAddress,) =
                    abi.decode(entries[i].data, (address, address, address));
                break;
            }
        }

        console.log("  Token:", tokenAddress);
        console.log("  Bonding Curve:", bondingCurveAddress);
        console.log("");
    }

    function testBuyFlow(CreatorCoin token, BondingCurve curve, address bondingCurveAddress)
        internal
        returns (uint256 tokensReceived)
    {
        console.log("Step 2: Recording initial balances...");
        uint256 userFlkBefore = IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER);
        uint256 foundationFlkBefore = IERC20(FLK_TOKEN).balanceOf(FOUNDATION);
        console.log("  User FLK:", userFlkBefore / 1e18);
        console.log("  Foundation FLK:", foundationFlkBefore / 1e18);
        console.log("");

        console.log("Step 3: Buying 1000 FLK worth of tokens...");
        IERC20(FLK_TOKEN).approve(bondingCurveAddress, type(uint256).max);

        vm.recordLogs();
        curve.buy(1000e18, 0);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 buyFee = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Buy(address,uint256,uint256,uint256)")) {
                (,, buyFee) = abi.decode(entries[i].data, (uint256, uint256, uint256));
                break;
            }
        }

        tokensReceived = token.balanceOf(ACTUAL_USER);
        uint256 userFlkAfter = IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER);
        uint256 foundationFlkAfter = IERC20(FLK_TOKEN).balanceOf(FOUNDATION);
        uint256 actualSpent = userFlkBefore - userFlkAfter;

        console.log("  Tokens received:", tokensReceived / 1e18);
        console.log("  FLK spent (total):", actualSpent / 1e18);
        console.log("  Buy fee charged:", buyFee / 1e18);
        console.log("  Fee percentage:", (buyFee * 10000) / (actualSpent - buyFee) / 100, "%");
        console.log("  Foundation received:", (foundationFlkAfter - foundationFlkBefore) / 1e18);
        console.log("");
    }

    function checkAndWaitForLockExpiry(CreatorCoin token) internal returns (uint256 lockUntil) {
        console.log("Step 4: Checking transfer lock status...");
        lockUntil = token.transferLockedUntil(ACTUAL_USER);
        uint256 lockDuration = lockUntil - block.timestamp;
        console.log("  Lock active until:", lockUntil);
        console.log("  Current time:", block.timestamp);
        console.log("  Lock duration:", lockDuration, "seconds (30-120s expected)");
        console.log("  Waiting for lock to expire...");
        console.log("");

        vm.warp(lockUntil + 1);
        console.log("  Lock expired! Time fast-forwarded to:", block.timestamp);
        console.log("");
    }

    function testSellFlow(
        CreatorCoin token,
        BondingCurve curve,
        address bondingCurveAddress,
        uint256 tokensReceived
    ) internal {
        console.log("Step 5: Selling half the tokens (testing anti-flip fee)...");
        uint256 sellAmount = tokensReceived / 2;

        console.log("  Selling:", sellAmount / 1e18, "tokens");
        console.log("");

        token.approve(bondingCurveAddress, sellAmount);
        uint256 userFlkBefore = IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER);
        uint256 foundationFlkBefore = IERC20(FLK_TOKEN).balanceOf(FOUNDATION);

        vm.recordLogs();
        curve.sell(sellAmount, 0);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 sellFee = 0;
        uint256 flkReceived = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Sell(address,uint256,uint256,uint256)")) {
                (, flkReceived, sellFee) = abi.decode(entries[i].data, (uint256, uint256, uint256));
                break;
            }
        }

        uint256 userFlkAfter = IERC20(FLK_TOKEN).balanceOf(ACTUAL_USER);
        uint256 foundationFlkAfter = IERC20(FLK_TOKEN).balanceOf(FOUNDATION);
        uint256 netFlkReceived = userFlkAfter - userFlkBefore;
        uint256 foundationFeeReceived = foundationFlkAfter - foundationFlkBefore;

        console.log("=== Sell Results ===");
        console.log("  Gross FLK (before fees):", flkReceived / 1e18);
        console.log("  Net FLK received:", netFlkReceived / 1e18);
        console.log("  Total fee:", sellFee / 1e18);
        console.log("  Actual fee percentage:", (sellFee * 10000) / flkReceived / 100, "%");
        console.log("");
        console.log("  Fee breakdown:");
        console.log("    Foundation:", foundationFeeReceived / 1e18, "FLK");
        console.log("    Creator:", (sellFee - foundationFeeReceived) / 1e18, "FLK");
        console.log("");

        console.log("=== Test Summary ===");
        console.log("  Sell fee:", (sellFee * 10000) / flkReceived / 100, "% (expected: 2-12%)");
    }
}
