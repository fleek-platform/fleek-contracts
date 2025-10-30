// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/libraries/LinearCurveMath.sol";

/**
 * @title LinearCurveMathV4EdgeCasesTest
 * @notice Comprehensive edge case testing to improve branch coverage
 * @dev Focuses on: error conditions, non-standard decimals, helper functions, and boundary cases
 */
contract LinearCurveMathV4EdgeCasesTest is Test {
    using LinearCurveMathV4 for *;

    // Standard test parameters
    uint256 constant TARGET_AMOUNT = 10_000e18;
    uint256 constant MAX_SUPPLY = 100_000e18;
    uint256 constant BASE_PRICE = 0.01e18;

    // Different decimal configurations
    uint8 constant DECIMALS_6 = 6;
    uint8 constant DECIMALS_8 = 8;
    uint8 constant DECIMALS_18 = 18;

    function setUp() public { }

    // ============ CONVERTPRICE FUNCTION TESTS ============

    function test_ConvertPrice_SameDecimals() public pure {
        uint256 price = 1000e6;
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_6, DECIMALS_6);
        assertEq(result, price, "Same decimals should return unchanged price");
    }

    function test_ConvertPrice_ScaleUp_6to18() public pure {
        uint256 price = 1000e6; // 1000 with 6 decimals
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_6, DECIMALS_18);
        // Should multiply by 10^(18-6) = 10^12
        assertEq(result, 1000e18, "Should scale up from 6 to 18 decimals");
    }

    function test_ConvertPrice_ScaleUp_8to18() public pure {
        uint256 price = 500e8; // 500 with 8 decimals
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_8, DECIMALS_18);
        // Should multiply by 10^(18-8) = 10^10
        assertEq(result, 500e18, "Should scale up from 8 to 18 decimals");
    }

    function test_ConvertPrice_ScaleDown_18to6() public pure {
        uint256 price = 2000e18; // 2000 with 18 decimals
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_18, DECIMALS_6);
        // Should divide by 10^(18-6) = 10^12
        assertEq(result, 2000e6, "Should scale down from 18 to 6 decimals");
    }

    function test_ConvertPrice_ScaleDown_18to8() public pure {
        uint256 price = 1500e18; // 1500 with 18 decimals
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_18, DECIMALS_8);
        // Should divide by 10^(18-8) = 10^10
        assertEq(result, 1500e8, "Should scale down from 18 to 8 decimals");
    }

    function test_ConvertPrice_6to8() public pure {
        uint256 price = 100e6;
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_6, DECIMALS_8);
        // Should multiply by 10^(8-6) = 100
        assertEq(result, 100e8, "Should scale up from 6 to 8 decimals");
    }

    function test_ConvertPrice_8to6() public pure {
        uint256 price = 200e8;
        uint256 result = LinearCurveMathV4.convertPrice(price, DECIMALS_8, DECIMALS_6);
        // Should divide by 10^(8-6) = 100
        assertEq(result, 200e6, "Should scale down from 8 to 6 decimals");
    }

    // ============ DECIMAL HANDLING EDGE CASES ============

    function test_MixedDecimals_6And8() public pure {
        uint256 targetAmount = 1000e6; // Sell token with 6 decimals
        uint256 maxSupply = 10000e8; // Buy token with 8 decimals
        uint256 basePrice = 0.01e6; // Price in sell token terms

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_8, DECIMALS_6
        );

        assertGt(finalPriceVal, 0, "Should handle 6/8 decimal mix");

        uint256 slopeVal =
            LinearCurveMathV4.slope(finalPriceVal, basePrice, maxSupply, DECIMALS_8, DECIMALS_6);

        assertGt(slopeVal, 0, "Slope should be positive");
    }

    function test_BuyWithMixedDecimals_6And8() public pure {
        uint256 targetAmount = 1000e6;
        uint256 maxSupply = 10000e8;
        uint256 basePrice = 0.01e6;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_8, DECIMALS_6
        );

        uint256 slopeVal =
            LinearCurveMathV4.slope(finalPriceVal, basePrice, maxSupply, DECIMALS_8, DECIMALS_6);

        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            1e6, // 1 sell token with 6 decimals
            0,
            basePrice,
            slopeVal,
            DECIMALS_8,
            DECIMALS_6
        );

        assertGt(buyAmount, 0, "Should calculate buy amount with mixed decimals");
    }

    function test_SellWithMixedDecimals_6And8() public pure {
        uint256 targetAmount = 1000e6;
        uint256 maxSupply = 10000e8;
        uint256 basePrice = 0.01e6;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_8, DECIMALS_6
        );

        uint256 slopeVal =
            LinearCurveMathV4.slope(finalPriceVal, basePrice, maxSupply, DECIMALS_8, DECIMALS_6);

        uint256 sellAmount = LinearCurveMathV4.calculateSellAmount(
            100e8, // 100 buy tokens with 8 decimals
            1000e8, // Current supply
            basePrice,
            slopeVal,
            DECIMALS_8,
            DECIMALS_6
        );

        assertGt(sellAmount, 0, "Should calculate sell amount with mixed decimals");
    }

    function test_BuyCostWithMixedDecimals() public pure {
        uint256 targetAmount = 1000e6;
        uint256 maxSupply = 10000e8;
        uint256 basePrice = 0.01e6;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_8, DECIMALS_6
        );

        uint256 slopeVal =
            LinearCurveMathV4.slope(finalPriceVal, basePrice, maxSupply, DECIMALS_8, DECIMALS_6);

        uint256 cost = LinearCurveMathV4.calculateBuyCost(
            50e8, // Want 50 buy tokens
            100e8, // At supply 100
            basePrice,
            slopeVal,
            DECIMALS_8,
            DECIMALS_6
        );

        assertGt(cost, 0, "Should calculate buy cost with mixed decimals");
    }

    function test_SellCostWithMixedDecimals() public pure {
        uint256 targetAmount = 1000e6;
        uint256 maxSupply = 10000e8;
        uint256 basePrice = 0.01e6;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_8, DECIMALS_6
        );

        uint256 slopeVal =
            LinearCurveMathV4.slope(finalPriceVal, basePrice, maxSupply, DECIMALS_8, DECIMALS_6);

        uint256 sellCost = LinearCurveMathV4.calculateSellCost(
            10e6, // Want 10 sell tokens out
            1000e8, // Current supply
            basePrice,
            slopeVal,
            DECIMALS_8,
            DECIMALS_6
        );

        assertGt(sellCost, 0, "Should calculate sell cost with mixed decimals");
        assertLe(sellCost, 1000e8, "Sell cost should not exceed supply");
    }

    // ============ ERROR CONDITION TESTS ============

    function test_Revert_InvalidDecimals() public {
        // Test with buyTokenDecimals > 18
        vm.expectRevert(LinearCurveMathV4.InvalidDecimals.selector);
        this.callFinalPriceWithInvalidBuyDecimals();

        // Test with sellTokenDecimals > 18
        vm.expectRevert(LinearCurveMathV4.InvalidDecimals.selector);
        this.callFinalPriceWithInvalidSellDecimals();

        // Test with both > 18
        vm.expectRevert(LinearCurveMathV4.InvalidDecimals.selector);
        this.callFinalPriceWithBothInvalidDecimals();
    }

    function callFinalPriceWithInvalidBuyDecimals() external pure {
        LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT,
            MAX_SUPPLY,
            BASE_PRICE,
            19, // Invalid: > 18
            DECIMALS_18
        );
    }

    function callFinalPriceWithInvalidSellDecimals() external pure {
        LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT,
            MAX_SUPPLY,
            BASE_PRICE,
            DECIMALS_18,
            20 // Invalid: > 18
        );
    }

    function callFinalPriceWithBothInvalidDecimals() external pure {
        LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT,
            MAX_SUPPLY,
            BASE_PRICE,
            25, // Invalid
            30 // Invalid
        );
    }

    function test_Revert_InvalidSlope() public {
        vm.expectRevert(LinearCurveMathV4.InvalidSlope.selector);
        this.callBuyAmountWithZeroSlope();
    }

    function callBuyAmountWithZeroSlope() external pure {
        LinearCurveMathV4.calculateBuyAmount(
            1e18,
            0,
            BASE_PRICE,
            0, // Invalid: slope = 0
            DECIMALS_18,
            DECIMALS_18
        );
    }

    function test_Revert_OutputTooSmall() public {
        // Use parameters that result in outputFP = 0 after unwrap
        // This happens with very small input amounts
        vm.expectRevert(LinearCurveMathV4.OutputTooSmall.selector);
        this.callBuyAmountWithTinyInput();
    }

    function callBuyAmountWithTinyInput() external pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        // Use an extremely tiny input at very high supply to trigger outputFP = 0
        LinearCurveMathV4.calculateBuyAmount(
            1, // 1 wei - extremely small
            MAX_SUPPLY - 1e18, // Very high supply
            BASE_PRICE,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
    }

    function test_Revert_FinalPriceBelowBase() public {
        // Create scenario where finalPrice < basePrice
        uint256 highBasePrice = 1e18; // High base price
        uint256 smallTarget = 1e18; // Small target
        uint256 largeSupply = 1000e18; // Large supply

        // (2 * 1e18 / 1000e18) - 1e18 = 0.002e18 - 1e18 = negative
        vm.expectRevert(LinearCurveMathV4.FinalPriceBelowBase.selector);
        this.callSlopeWithFinalBelowBase(highBasePrice, smallTarget, largeSupply);
    }

    function callSlopeWithFinalBelowBase(
        uint256 basePrice,
        uint256 targetAmount,
        uint256 maxSupply
    ) external pure {
        // First calculate a final price that's lower than base
        // (2 * target / supply) needs to be less than basePrice
        uint256 lowFinalPrice = 0.5e18; // Lower than typical base

        LinearCurveMathV4.slope(
            lowFinalPrice, // This is less than basePrice
            basePrice, // Higher than finalPrice
            maxSupply,
            DECIMALS_18,
            DECIMALS_18
        );
    }

    function test_Revert_InvalidMaxSupply_InSlope() public {
        uint256 finalPriceVal = 1e18;
        uint256 basePrice = 0.5e18;

        vm.expectRevert(LinearCurveMathV4.InvalidMaxSupply.selector);
        this.callSlopeWithZeroSupply(finalPriceVal, basePrice);
    }

    function callSlopeWithZeroSupply(uint256 finalPrice, uint256 basePrice) external pure {
        LinearCurveMathV4.slope(
            finalPrice,
            basePrice,
            0, // Invalid: zero supply
            DECIMALS_18,
            DECIMALS_18
        );
    }

    function test_Revert_InvalidInputAmount_InSellAmount() public {
        uint256 slopeVal = 1e12;

        vm.expectRevert(LinearCurveMathV4.InvalidInputAmount.selector);
        this.callSellAmountWithZeroInput(slopeVal);
    }

    function callSellAmountWithZeroInput(uint256 slopeVal) external pure {
        LinearCurveMathV4.calculateSellAmount(
            0, // Invalid: zero input
            1000e18,
            BASE_PRICE,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
    }

    function test_Revert_InvalidInputAmount_InBuyCost() public {
        uint256 slopeVal = 1e12;

        vm.expectRevert(LinearCurveMathV4.InvalidInputAmount.selector);
        this.callBuyCostWithZeroOutput(slopeVal);
    }

    function callBuyCostWithZeroOutput(uint256 slopeVal) external pure {
        LinearCurveMathV4.calculateBuyCost(
            0, // Invalid: zero output
            1000e18,
            BASE_PRICE,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
    }

    // ============ BOUNDARY AND EDGE CASES ============

    function test_VerySmallSlope() public pure {
        // Create scenario with very small but valid slope
        uint256 targetAmount = 200_000e18; // Higher target to avoid underflow
        uint256 maxSupply = 1_000_000e18; // Large supply
        uint256 basePrice = 1e15; // Very low base

        // (2 * 200000e18 / 1000000e18) - 1e15 = 0.4e18 - 0.001e18 = 0.399e18
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_18, DECIMALS_18
        );

        assertGt(finalPriceVal, basePrice, "Final price should be above base");

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, basePrice, maxSupply, DECIMALS_18, DECIMALS_18
        );

        // Slope should be very small but positive
        assertGt(slopeVal, 0, "Slope should be positive");
        assertLt(slopeVal, 1e12, "Slope should be very small");

        // Should still be able to buy
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            1e18, 0, basePrice, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(buyAmount, 0, "Should be able to buy with very small slope");
    }

    function test_ExtremeSupplyPosition() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        // Buy at extreme supply position (near max)
        uint256 nearMaxSupply = MAX_SUPPLY - 100e18;
        uint256 cost = LinearCurveMathV4.calculateBuyCost(
            10e18, nearMaxSupply, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(cost, 0, "Should handle extreme supply positions");

        // Verify price is much higher near max
        uint256 costAtStart = LinearCurveMathV4.calculateBuyCost(
            10e18, 0, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(cost, costAtStart * 10, "Cost near max should be significantly higher");
    }

    function test_MinimalBuyAmount() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        // Buy minimal amount at low supply
        uint256 minInput = 1e15; // 0.001 tokens
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            minInput, 0, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(buyAmount, 0, "Should handle minimal buy amounts");
    }

    function test_FullCurvePurchase() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        // Buy entire curve from start to finish
        uint256 totalCost = LinearCurveMathV4.calculateBuyCost(
            MAX_SUPPLY, 0, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should be close to target amount
        assertApproxEqRel(
            totalCost, TARGET_AMOUNT, 0.01e18, "Full curve purchase should match target amount"
        );
    }

    function test_SellEntireSupply() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        uint256 currentSupply = 1000e18;

        // Sell entire current supply
        uint256 sellReturn = LinearCurveMathV4.calculateSellAmount(
            currentSupply, currentSupply, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(sellReturn, 0, "Should be able to sell entire supply");

        // Verify selling entire supply returns less than or equal to what it cost to buy it
        uint256 buyCost = LinearCurveMathV4.calculateBuyCost(
            currentSupply, 0, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertLe(sellReturn, buyCost, "Sell should return at most the buy cost");
    }

    function test_ZeroSupplySellAmount() public {
        // Attempting to sell from zero supply should revert
        uint256 slopeVal = 1e12;

        vm.expectRevert(LinearCurveMathV4.InsufficientLiquidity.selector);
        this.callSellAmountFromZeroSupply(slopeVal);
    }

    function callSellAmountFromZeroSupply(uint256 slopeVal) external pure {
        LinearCurveMathV4.calculateSellAmount(
            1e18,
            0, // Zero supply
            BASE_PRICE,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );
    }

    function test_HighPrecisionDecimals() public pure {
        // Test with maximum allowed decimals (18)
        uint256 targetAmount = 2000e18; // Higher to ensure final price > base
        uint256 maxSupply = 10000e18;
        uint256 basePrice = 0.01e18; // Lower base price

        // (2 * 2000e18 / 10000e18) - 0.01e18 = 0.4e18 - 0.01e18 = 0.39e18
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, basePrice, maxSupply, DECIMALS_18, DECIMALS_18
        );

        assertGt(slopeVal, 0, "Slope should be positive");

        // Perform operations with high precision
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            1e18, 5000e18, basePrice, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(buyAmount, 0, "Should handle 18 decimal precision correctly");
    }

    function test_DecimalConversion_Precision() public pure {
        // Test that decimal conversion maintains precision
        uint256 amount6 = 123456e6; // 123456.000000
        uint256 amount18 = LinearCurveMathV4.convertPrice(amount6, DECIMALS_6, DECIMALS_18);
        uint256 backTo6 = LinearCurveMathV4.convertPrice(amount18, DECIMALS_18, DECIMALS_6);

        assertEq(backTo6, amount6, "Round-trip conversion should preserve value");
    }

    function test_SellCost_WithHighOutput() public pure {
        // Test calculateSellCost when output is substantial portion of supply
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        uint256 currentSupply = 10000e18; // Higher supply to handle higher output
        uint256 desiredOutput = 50e18; // Want 50 sell tokens

        uint256 sellCost = LinearCurveMathV4.calculateSellCost(
            desiredOutput, currentSupply, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(sellCost, 0, "Should calculate cost for high output");
        assertLe(sellCost, currentSupply, "Cost should not exceed supply");

        // Verify by actually selling
        uint256 actualOutput = LinearCurveMathV4.calculateSellAmount(
            sellCost, currentSupply, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertApproxEqRel(actualOutput, desiredOutput, 0.01e18, "Should produce desired output");
    }

    function test_BuyAndSellCost_Symmetry() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT, MAX_SUPPLY, BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE, MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        uint256 supply = 5000e18;
        uint256 amount = 100e18;

        // Calculate cost to buy
        uint256 buyCost = LinearCurveMathV4.calculateBuyCost(
            amount, supply, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // After buying, supply increases
        uint256 newSupply = supply + amount;

        // Calculate what we'd get selling the same amount back
        uint256 sellReturn = LinearCurveMathV4.calculateSellAmount(
            amount, newSupply, BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should get approximately the same (minus rounding)
        assertApproxEqRel(
            sellReturn, buyCost, 0.001e18, "Buy cost and immediate sell should be symmetric"
        );
    }
}
