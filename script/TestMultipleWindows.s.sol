// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { AntiFlipFeeLib } from "../src/creator-tokens/libraries/AntiFlipFeeLib.sol";

contract TestMultipleWindows is Script {
    function run() public pure {
        address user = 0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9;
        address token = 0xd10F79862FF3654eF6629831669Be71AC92eE796;
        uint256 entropyTs = 1761599438;

        console.log("=== Testing Window Randomness ===");
        console.log("");

        // First buy
        uint256 buy1 = 1761599992;
        uint256 window1 = AntiFlipFeeLib.calculateWindow(user, token, buy1, entropyTs);
        console.log("Buy 1:");
        console.log("  Timestamp:", buy1);
        console.log("  Window:   ", window1, "seconds");
        console.log("");

        // Second buy
        uint256 buy2 = 1761600164;
        uint256 window2 = AntiFlipFeeLib.calculateWindow(user, token, buy2, entropyTs);
        console.log("Buy 2:");
        console.log("  Timestamp:", buy2);
        console.log("  Window:   ", window2, "seconds");
        console.log("");

        // Third buy (hypothetical - +5 minutes)
        uint256 buy3 = 1761600464;
        uint256 window3 = AntiFlipFeeLib.calculateWindow(user, token, buy3, entropyTs);
        console.log("Buy 3 (hypothetical +5min):");
        console.log("  Timestamp:", buy3);
        console.log("  Window:   ", window3, "seconds");
        console.log("");

        // Fourth buy (hypothetical - +1 hour)
        uint256 buy4 = 1761603592;
        uint256 window4 = AntiFlipFeeLib.calculateWindow(user, token, buy4, entropyTs);
        console.log("Buy 4 (hypothetical +1hr):");
        console.log("  Timestamp:", buy4);
        console.log("  Window:   ", window4, "seconds");
        console.log("");

        console.log("Window Comparison:");
        console.log("  Buy1 == Buy2:", window1 == window2);
        console.log("  Buy2 == Buy3:", window2 == window3);
        console.log("  Buy3 == Buy4:", window3 == window4);
        console.log("");
        console.log("Expected: All different (30-120 seconds range)");
    }
}
