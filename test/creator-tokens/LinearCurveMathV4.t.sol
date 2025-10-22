// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/lib/LinearCurveMath.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract LinearCurveMathV4Test is Test {
    using LinearCurveMathV4 for *;

    // Test constants
    uint256 constant TARGET_AMOUNT_18 = 1000e18; // 1000 sell tokens (18 decimals)
    uint256 constant MAX_SUPPLY_18 = 10000e18; // 10000 buy tokens (18 decimals)
    uint256 constant BASE_PRICE_18 = 1e18; // 1 sell token per buy token (18 decimals)
    
    // Different decimal configs for testing
    uint8 constant DECIMALS_6 = 6;
    uint8 constant DECIMALS_8 = 8;
    uint8 constant DECIMALS_18 = 18;

    function setUp() public {}

    // Test 1: Final Price Calculation with Standard 18 Decimals
    function test_FinalPriceCalculation_18Decimals() public pure {
        uint256 finalPriceResult = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Expected: (2 * 1000e18 / 10000e18) + 1e18 = 0.2e18 + 1e18 = 1.2e18
        assertEq(finalPriceResult, 1.2e18, "Final price should be 1.2 with 18 decimals");
    }

    // Test 2: Final Price with Mixed Decimals (6 and 18)
    function test_FinalPriceCalculation_MixedDecimals() public pure {
        uint256 targetAmount6 = 1000e6; // 1000 tokens with 6 decimals
        uint256 maxSupply8 = 10000e8; // 10000 tokens with 8 decimals
        uint256 basePrice6 = 1e6; // 1 unit price with 6 decimals
        
        uint256 finalPriceResult = LinearCurveMathV4.finalPrice(
            targetAmount6,
            maxSupply8,
            basePrice6,
            DECIMALS_8,
            DECIMALS_6
        );
        
        // Expected: (2 * 1000 / 10000) + 1 = 0.2 + 1 = 1.2 (in 6 decimals = 1.2e6)
        assertEq(finalPriceResult, 1.2e6, "Final price should handle mixed decimals correctly");
    }

    // Test 3: Slope Calculation and Consistency
    function test_SlopeCalculation() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            BASE_PRICE_18,
            MAX_SUPPLY_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Slope = (1.2e18 - 1e18) / 10000e18 = 0.2e18 / 10000e18 = 0.00002e18 = 2e13
        assertEq(slopeVal, 2e13, "Slope calculation should be correct");
    }

    // Test 4: Buy Amount Calculation (Quadratic Formula)
    function test_CalculateBuyAmount_StandardCase() public pure {
        uint256 inputAmount = 100e18; // 100 sell tokens
        uint256 currentSupply = 1000e18; // 1000 already sold
        
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            BASE_PRICE_18,
            MAX_SUPPLY_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            inputAmount,
            currentSupply,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Should get some positive amount of buy tokens
        assertGt(buyAmount, 0, "Should receive buy tokens for sell tokens");
        assertLt(buyAmount, inputAmount, "Due to bonding curve, should get less than 1:1 at this position");
    }

    // Test 5: Buy Amount at Zero Supply (Edge Case)
    function test_CalculateBuyAmount_ZeroSupply() public pure {
        uint256 inputAmount = 10e18; // 10 sell tokens
        uint256 currentSupply = 0; // Starting position
        
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            BASE_PRICE_18,
            MAX_SUPPLY_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            inputAmount,
            currentSupply,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // At zero supply with base price of 1, should get approximately 10 tokens
        assertGt(buyAmount, 9e18, "Should get close to input amount at zero supply");
        assertLe(buyAmount, 10e18, "Should not exceed input amount at base price");
    }

    // Test 6: Sell Amount Calculation
    function test_CalculateSellAmount() public pure {
        uint256 inputAmount = 100e18; // 100 buy tokens to sell
        uint256 currentSupply = 1000e18; // 1000 supply
        
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            BASE_PRICE_18,
            MAX_SUPPLY_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 sellAmount = LinearCurveMathV4.calculateSellAmount(
            inputAmount,
            currentSupply,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Should receive sell tokens
        assertGt(sellAmount, 0, "Should receive sell tokens for buy tokens");
        
        // Price should be higher than base due to position on curve
        assertGt(sellAmount, inputAmount * BASE_PRICE_18 / 1e18, "Should get more than base price due to curve position");
    }

    // Test 7: Buy/Sell Reversibility (Important Invariant)
    function test_BuySellReversibility() public pure {
        uint256 initialSupply = 500e18;
        uint256 buyInput = 50e18; // Buy with 50 sell tokens
        
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            BASE_PRICE_18,
            MAX_SUPPLY_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // First buy tokens
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            buyInput,
            initialSupply,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Then sell them back
        uint256 sellOutput = LinearCurveMathV4.calculateSellAmount(
            buyAmount,
            initialSupply + buyAmount,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Should get approximately the same amount back (small rounding difference ok)
        assertApproxEqRel(sellOutput, buyInput, 0.001e18, "Buy then sell should be approximately reversible");
    }

    // Test 8: Calculate Buy Cost (Exact Output)
    function test_CalculateBuyCost() public pure {
        uint256 desiredOutput = 100e18; // Want exactly 100 buy tokens
        uint256 currentSupply = 1000e18;
        
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18,
            MAX_SUPPLY_18,
            BASE_PRICE_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            BASE_PRICE_18,
            MAX_SUPPLY_18,
            DECIMALS_18,
            DECIMALS_18
        );
        
        uint256 cost = LinearCurveMathV4.calculateBuyCost(
            desiredOutput,
            currentSupply,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        // Verify by using the cost to buy and checking output
        uint256 actualOutput = LinearCurveMathV4.calculateBuyAmount(
            cost,
            currentSupply,
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
        
        assertApproxEqRel(actualOutput, desiredOutput, 0.001e18, "Buy cost should produce desired output");
    }

    // Test 9: Error Conditions and Reverts  
    function test_ErrorConditions() public {
        // Test InvalidTargetAmount
        vm.expectRevert(LinearCurveMathV4.InvalidTargetAmount.selector);
        this.callFinalPriceWithZeroTarget();
        
        // Test InvalidMaxSupply
        vm.expectRevert(LinearCurveMathV4.InvalidMaxSupply.selector);
        this.callFinalPriceWithZeroSupply();
        
        // Test FinalPriceBelowBase
        vm.expectRevert(LinearCurveMathV4.FinalPriceBelowBase.selector);
        this.callSlopeWithLowFinalPrice();
        
        // Test InsufficientLiquidity in sell
        vm.expectRevert(LinearCurveMathV4.InsufficientLiquidity.selector);
        this.callSellWithInsufficientLiquidity();
        
        // Test InvalidInputAmount
        vm.expectRevert(LinearCurveMathV4.InvalidInputAmount.selector);
        this.callBuyWithZeroAmount();
    }
    
    // Helper functions for error testing (need to be external for try/catch)
    function callFinalPriceWithZeroTarget() external pure {
        LinearCurveMathV4.finalPrice(0, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18);
    }
    
    function callFinalPriceWithZeroSupply() external pure {
        LinearCurveMathV4.finalPrice(TARGET_AMOUNT_18, 0, BASE_PRICE_18, DECIMALS_18, DECIMALS_18);
    }
    
    function callSlopeWithLowFinalPrice() external pure {
        LinearCurveMathV4.slope(0.5e18, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18);
    }
    
    function callSellWithInsufficientLiquidity() external pure {
        uint256 slopeVal = 2e13;
        LinearCurveMathV4.calculateSellAmount(
            200e18, // Try to sell 200
            100e18, // Only 100 supply available
            BASE_PRICE_18,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
    }
    
    function callBuyWithZeroAmount() external pure {
        uint256 slopeVal = 2e13;
        LinearCurveMathV4.calculateBuyAmount(0, 1000e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18);
    }

    // Test 10: Fuzz Test for Decimal Handling
    function testFuzz_DecimalHandling(
        uint8 buyDecimals,
        uint8 sellDecimals,
        uint256 targetAmount,
        uint256 maxSupply
    ) public pure {
        // Bound decimals to reasonable values
        buyDecimals = uint8(bound(buyDecimals, 4, 18));
        sellDecimals = uint8(bound(sellDecimals, 4, 18));
        
        // Create reasonable amounts for each decimal
        targetAmount = bound(targetAmount, 10 ** sellDecimals, 1000000 * 10 ** sellDecimals);
        maxSupply = bound(maxSupply, 10 ** buyDecimals, 1000000 * 10 ** buyDecimals);
        uint256 basePrice = 10 ** sellDecimals; // 1:1 base price
        
        // Should not revert with valid decimal inputs
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount,
            maxSupply,
            basePrice,
            buyDecimals,
            sellDecimals
        );
        
        // Final price should be greater than or equal to base price (equal when targetAmount approaches 0)
        assertGe(finalPriceVal, basePrice, "Final price should be at least base price");
        
        // Calculate slope should work
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal,
            basePrice,
            maxSupply,
            buyDecimals,
            sellDecimals
        );
        
        assertGe(slopeVal, 0, "Slope should be non-negative");
        
        // Only test buy calculation if slope is positive (otherwise it would revert)
        if (slopeVal > 0) {
            // Buy calculation should work
            uint256 inputAmount = 100 * 10 ** sellDecimals;
            uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
                inputAmount,
                0,
                basePrice,
                slopeVal,
                buyDecimals,
                sellDecimals
            );
            
            assertGt(buyAmount, 0, "Should receive tokens for any valid decimal configuration");
        }
    }
}