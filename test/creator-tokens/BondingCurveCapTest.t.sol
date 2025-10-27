// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/libraries/LinearCurveMath.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";

contract BondingCurveCapTest is Test {
    function test_CalculateBuyCostNearGraduation() public view {
        // Current state from testnet
        uint256 characterTokensSold = 224477971024000000000000; // ~224,477.97 tokens sold (exact wei from testnet)
        uint256 maxAvailable = (Config.BONDING_CURVE_ALLOCATION / 2) - characterTokensSold;
        
        console.log("Tokens sold:", characterTokensSold / 1e18);
        console.log("Max available:", maxAvailable / 1e18);
        console.log("Progress:", (characterTokensSold * 100) / (Config.BONDING_CURVE_ALLOCATION / 2), "%");
        
        // Calculate slope
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
        
        console.log("Slope:", slope);
        
        // Try to calculate the cost to buy the remaining tokens
        console.log("\n=== Testing calculateBuyCost ===");
        try this.externalCalculateBuyCost(
            maxAvailable,
            characterTokensSold,
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        ) returns (uint256 cost) {
            console.log("Cost for remaining tokens:", cost / 1e18, "FLK");
            console.log("SUCCESS: calculateBuyCost works for remaining amount");
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED with no reason (likely overflow/underflow)");
        }
        
        // Now test with a larger input (200 FLK worth)
        console.log("\n=== Testing calculateBuyAmount with 200 FLK ===");
        uint256 inputAmount = 200e18;
        try this.externalCalculateBuyAmount(
            inputAmount,
            characterTokensSold,
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        ) returns (uint256 buyAmount) {
            console.log("200 FLK buys:", buyAmount / 1e18, "tokens");
            
            // If this exceeds maxAvailable, we should cap
            if (buyAmount > maxAvailable) {
                console.log("Exceeds max available, should cap to:", maxAvailable / 1e18);
                console.log("\n=== Testing calculateBuyCost for capped amount ===");
                
                try this.externalCalculateBuyCost(
                    maxAvailable,
                    characterTokensSold,
                    Config.BASE_PRICE,
                    slope,
                    Config.CREATOR_COIN_DECIMALS,
                    Config.FLK_DECIMALS
                ) returns (uint256 cappedCost) {
                    console.log("Capped cost:", cappedCost / 1e18, "FLK");
                    console.log("SUCCESS: Capping logic should work!");
                } catch Error(string memory reason) {
                    console.log("FAILED: calculateBuyCost reverted with:", reason);
                    console.log("THIS IS THE BUG!");
                } catch (bytes memory) {
                    console.log("FAILED: calculateBuyCost reverted with no reason");
                    console.log("THIS IS THE BUG!");
                }
            }
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED with no reason");
        }
    }
    
    // External wrappers to catch reverts
    function externalCalculateBuyCost(
        uint256 outputAmount,
        uint256 currentSupply,
        uint256 basePrice,
        uint256 slope,
        uint8 buyDecimals,
        uint8 sellDecimals
    ) external pure returns (uint256) {
        return LinearCurveMathV4.calculateBuyCost(
            outputAmount,
            currentSupply,
            basePrice,
            slope,
            buyDecimals,
            sellDecimals
        );
    }
    
    function externalCalculateBuyAmount(
        uint256 inputAmount,
        uint256 currentSupply,
        uint256 basePrice,
        uint256 slope,
        uint8 buyDecimals,
        uint8 sellDecimals
    ) external pure returns (uint256) {
        return LinearCurveMathV4.calculateBuyAmount(
            inputAmount,
            currentSupply,
            basePrice,
            slope,
            buyDecimals,
            sellDecimals
        );
    }
}
