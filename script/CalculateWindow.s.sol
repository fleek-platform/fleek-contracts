// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { AntiFlipFeeLib } from "../src/creator-tokens/libraries/AntiFlipFeeLib.sol";

contract CalculateWindow is Script {
    function run() public view {
        address user = 0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9;
        address token = 0xd10F79862FF3654eF6629831669Be71AC92eE796;
        uint256 buyTs = 1761600164;
        uint256 entropyTs = 1761599438;

        uint256 window = AntiFlipFeeLib.calculateWindow(user, token, buyTs, entropyTs);

        console.log("User:", user);
        console.log("Token:", token);
        console.log("Buy timestamp:", buyTs);
        console.log("Entropy timestamp:", entropyTs);
        console.log("Window:", window, "seconds");
        console.log("Expires at:", buyTs + window);
        console.log("");
        console.log("Current time:", block.timestamp);
        uint256 elapsed = block.timestamp > buyTs ? block.timestamp - buyTs : 0;
        console.log("Time elapsed:", elapsed, "seconds");
        if (block.timestamp < buyTs + window) {
            console.log("Status: WITHIN WINDOW - 12% fee on sells");
            console.log("Time remaining:", (buyTs + window) - block.timestamp, "seconds");
        } else {
            console.log("Status: OUTSIDE WINDOW - 2% fee on sells");
        }
    }
}
