// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/libraries/LinearCurveMath.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";

contract BondingCurveCapBugTest is Test {
    function test_SimulateBuyLogicAt99Percent() public view {
        // Exact state from testnet after 50 FLK buy
        uint256 characterTokensSold = 224477971024000000000000; // 224,477.97 tokens
        uint256 parentAmountIn = 200e18; // Trying to buy with 200 FLK

        console.log("=== SIMULATING BUY() LOGIC ===");
        console.log("Current sold:", characterTokensSold / 1e18);
        console.log("Attempting to buy with:", parentAmountIn / 1e18, "FLK");

        // Calculate slope (same as in initialize)
        uint256 finalPrice = LinearCurveMathV4.finalPrice(
            Config.GRADUATION_THRESHOLD,
            Config.BONDING_CURVE_ALLOCATION / 2,
            Config.BASE_PRICE,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        uint256 slope = LinearCurveMathV4.slope(
            finalPrice,
            Config.BASE_PRICE,
            Config.BONDING_CURVE_ALLOCATION / 2,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        console.log("\nStep 1: calculateBuyAmount");
        uint256 characterOut = LinearCurveMathV4.calculateBuyAmount(
            parentAmountIn,
            characterTokensSold,
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );
        console.log("characterOut:", characterOut / 1e18, "tokens");

        console.log("\nStep 2: Check if exceeds maxAvailable");
        uint256 maxAvailable = (Config.BONDING_CURVE_ALLOCATION / 2) - characterTokensSold;
        console.log("maxAvailable:", maxAvailable / 1e18, "tokens");

        uint256 curveCost = parentAmountIn;
        if (characterOut > maxAvailable) {
            console.log("YES - Capping to maxAvailable");
            characterOut = maxAvailable;

            console.log("\nStep 3: calculateBuyCost for capped amount");
            curveCost = LinearCurveMathV4.calculateBuyCost(
                characterOut,
                characterTokensSold,
                Config.BASE_PRICE,
                slope,
                Config.CREATOR_COIN_DECIMALS,
                Config.FLK_DECIMALS
            );
            console.log("curveCost:", curveCost / 1e18, "FLK");
        }

        console.log("\nStep 4: Check MIN_PURCHASE_FLK");
        uint256 MIN_PURCHASE_FLK = 1e17; // 0.1 FLK
        if (curveCost < MIN_PURCHASE_FLK) {
            console.log("ERROR: curveCost < MIN_PURCHASE_FLK!");
            console.log("This would revert with NotEnoughFLK()");
        } else {
            console.log("OK: curveCost >= MIN_PURCHASE_FLK");
        }

        console.log("\nStep 5: Check characterOut amount");
        if (characterOut == 0) {
            console.log("ERROR: characterOut is 0!");
        } else if (characterOut < 1e15) {
            console.log("WARNING: characterOut very small:", characterOut);
        } else {
            console.log("OK: characterOut is reasonable");
        }

        console.log("\n=== FINAL VALUES ===");
        console.log("Would buy:", characterOut / 1e18, "tokens");
        console.log("For cost:", curveCost / 1e18, "FLK");
        console.log("New sold:", (characterTokensSold + characterOut) / 1e18);
        console.log(
            "Progress:",
            ((characterTokensSold + characterOut) * 100) / (Config.BONDING_CURVE_ALLOCATION / 2),
            "%"
        );

        uint256 graduationThreshold = Config.BONDING_CURVE_ALLOCATION / 2;
        if (characterTokensSold + characterOut >= graduationThreshold) {
            console.log("\nWOULD TRIGGER GRADUATION!");
        }
    }
}
