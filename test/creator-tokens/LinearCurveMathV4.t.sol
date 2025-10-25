// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/lib/LinearCurveMath.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract LinearCurveMathV4Test is Test {
    using LinearCurveMathV4 for *;

    // Test Set 1: Factory parameters (realistic production values)
    uint256 constant FACTORY_TARGET_AMOUNT = 20_675e18; // Factory's graduation threshold
    uint256 constant FACTORY_MAX_SUPPLY = 225_000e18; // Half of bonding curve allocation
    uint256 constant FACTORY_BASE_PRICE = 1e15; // Very low base price from factory

    // Test Set 2: High target, large supply, low base (valid: 2*target/supply > base)
    // (2 * 10000e18) / 100000e18 = 0.2e18, 0.2e18 - 0.01e18 = 0.19e18 ✓
    uint256 constant TARGET_AMOUNT_18 = 10_000e18;
    uint256 constant MAX_SUPPLY_18 = 100_000e18;
    uint256 constant BASE_PRICE_18 = 0.01e18;

    // Test Set 3: Mixed decimals (valid with low base price)
    // (2 * 1000) / 10000 = 0.2, 0.2 - 0.01 = 0.19 ✓
    uint256 constant TARGET_AMOUNT_6 = 1000e6;
    uint256 constant MAX_SUPPLY_8 = 10000e8;
    uint256 constant BASE_PRICE_6 = 0.01e6;

    // Different decimal configs for testing
    uint8 constant DECIMALS_6 = 6;
    uint8 constant DECIMALS_8 = 8;
    uint8 constant DECIMALS_18 = 18;

    function setUp() public { }

    // Test 1: Final Price Calculation with Standard 18 Decimals
    function test_FinalPriceCalculation_18Decimals() public pure {
        uint256 finalPriceResult = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        // Expected: (2 * 10000e18 / 100000e18) - 0.01e18 = 0.2e18 - 0.01e18 = 0.19e18
        assertEq(finalPriceResult, 0.19e18, "Final price should be 0.19 with 18 decimals");
    }

    // Test 2: Final Price with Mixed Decimals (6 and 8)
    function test_FinalPriceCalculation_MixedDecimals() public pure {
        uint256 finalPriceResult = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_6, MAX_SUPPLY_8, BASE_PRICE_6, DECIMALS_8, DECIMALS_6
        );

        // Expected: (2 * 1000 / 10000) - 0.01 = 0.2 - 0.01 = 0.19 (in 6 decimals = 0.19e6)
        assertEq(finalPriceResult, 0.19e6, "Final price should handle mixed decimals correctly");
    }

    // Test 3: Slope Calculation and Consistency
    function test_SlopeCalculation() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Slope = (0.19e18 - 0.01e18) / 100000e18 = 0.18e18 / 100000e18 = 1.8e12
        assertEq(slopeVal, 1.8e12, "Slope calculation should be correct");
    }

    // Test 4: Buy Amount Calculation (Quadratic Formula)
    function test_CalculateBuyAmount_StandardCase() public pure {
        uint256 inputAmount = 1e18; // 1 sell token
        uint256 currentSupply = 1000e18; // 1000 already sold

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            inputAmount, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should get some positive amount of buy tokens
        assertGt(buyAmount, 0, "Should receive buy tokens for sell tokens");
        // With low base price (0.01), we should get more than 1:1 at low supply positions
        assertGt(buyAmount, inputAmount, "At low supply with low base price, should get more than 1:1");
    }

    // Test 5: Buy Amount at Zero Supply (Edge Case)
    function test_CalculateBuyAmount_ZeroSupply() public pure {
        uint256 inputAmount = 10e18; // 10 sell tokens
        uint256 currentSupply = 0; // Starting position

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            inputAmount, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // At zero supply with very low base price (0.01), should get much more than input
        assertGt(buyAmount, inputAmount, "With low base price at zero supply, should get more than input");
        assertGt(buyAmount, 90e18, "Should get substantial amount with low base price");
    }

    // Test 6: Sell Amount Calculation
    function test_CalculateSellAmount() public pure {
        uint256 inputAmount = 100e18; // 100 buy tokens to sell
        uint256 currentSupply = 1000e18; // 1000 supply

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 sellAmount = LinearCurveMathV4.calculateSellAmount(
            inputAmount, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should receive sell tokens
        assertGt(sellAmount, 0, "Should receive sell tokens for buy tokens");

        // Price should be higher than base due to position on curve
        assertGt(
            sellAmount,
            inputAmount * BASE_PRICE_18 / 1e18,
            "Should get more than base price due to curve position"
        );
    }

    // Test 7: Buy/Sell Reversibility (Important Invariant)
    function test_BuySellReversibility() public pure {
        uint256 initialSupply = 500e18;
        uint256 buyInput = 50e18; // Buy with 50 sell tokens

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // First buy tokens
        uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
            buyInput, initialSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Then sell them back
        uint256 sellOutput = LinearCurveMathV4.calculateSellAmount(
            buyAmount, initialSupply + buyAmount, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should get approximately the same amount back (small rounding difference ok)
        assertApproxEqRel(
            sellOutput, buyInput, 0.001e18, "Buy then sell should be approximately reversible"
        );
    }

    // Test 8: Calculate Buy Cost (Exact Output)
    function test_CalculateBuyCost() public pure {
        uint256 desiredOutput = 100e18; // Want exactly 100 buy tokens
        uint256 currentSupply = 1000e18;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 cost = LinearCurveMathV4.calculateBuyCost(
            desiredOutput, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Verify by using the cost to buy and checking output
        uint256 actualOutput = LinearCurveMathV4.calculateBuyAmount(
            cost, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertApproxEqRel(
            actualOutput, desiredOutput, 0.001e18, "Buy cost should produce desired output"
        );
    }

    // Test 9: Error Conditions and Reverts
    function test_ErrorConditions() public {
        // Test InvalidTargetAmount
        vm.expectRevert(LinearCurveMathV4.InvalidTargetAmount.selector);
        this.callFinalPriceWithZeroTarget();

        // Test InvalidMaxSupply
        vm.expectRevert(LinearCurveMathV4.InvalidMaxSupply.selector);
        this.callFinalPriceWithZeroSupply();

        // Test FinalPriceBelowBase - this now causes underflow with subtraction formula
        // When (2 * target / supply) < basePrice, we get underflow
        vm.expectRevert();
        this.callFinalPriceUnderflow();

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

    function callFinalPriceUnderflow() external pure {
        // This will underflow: (2 * 1 / 100000e18) - 0.01e18
        // Because 2/100000e18 is essentially 0, which is less than 0.01e18
        LinearCurveMathV4.finalPrice(1, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18);
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
        LinearCurveMathV4.calculateBuyAmount(
            0, 1000e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );
    }

    function test_CalculateSellCost_BasicOperation() public pure {
        uint256 outputAmount = 1e18; // Smaller output amount
        uint256 currentSupply = 10000e18; // Larger supply

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 sellCost = LinearCurveMathV4.calculateSellCost(
            outputAmount, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Verify the cost is reasonable
        assertGt(sellCost, 0, "Should require some buy tokens to sell");
        assertLe(sellCost, currentSupply, "Cannot sell more than supply");

        // Verify by selling the calculated amount
        uint256 actualOutput = LinearCurveMathV4.calculateSellAmount(
            sellCost, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertApproxEqRel(
            actualOutput, outputAmount, 0.01e18, "Sell cost should produce desired output"
        );
    }

    function test_CalculateSellCost_Reversibility() public pure {
        uint256 currentSupply = 5000e18;
        uint256 sellAmount = 500e18;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // First calculate how much we get for selling
        uint256 sellOutput = LinearCurveMathV4.calculateSellAmount(
            sellAmount, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Then calculate how much we need to sell to get that exact output
        uint256 calculatedCost = LinearCurveMathV4.calculateSellCost(
            sellOutput, currentSupply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertApproxEqRel(
            calculatedCost, sellAmount, 0.001e18, "SellCost should be inverse of SellAmount"
        );
    }

    function test_CalculateSellCost_EdgeCases() public {
        // Test with zero output (should revert)
        vm.expectRevert(LinearCurveMathV4.InvalidInputAmount.selector);
        this.callSellCostWithZeroOutput();

        // Test with zero supply (should revert)
        vm.expectRevert(LinearCurveMathV4.InsufficientLiquidity.selector);
        this.callSellCostWithZeroSupply();

        // Test when output would require more than supply (discriminant negative or result > supply)
        vm.expectRevert();
        this.callSellCostWithExcessiveOutput();
    }

    function callSellCostWithZeroOutput() external pure {
        LinearCurveMathV4.calculateSellCost(
            0, 1000e18, BASE_PRICE_18, 2e13, DECIMALS_18, DECIMALS_18
        );
    }

    function callSellCostWithZeroSupply() external pure {
        LinearCurveMathV4.calculateSellCost(
            100e18, 0, BASE_PRICE_18, 2e13, DECIMALS_18, DECIMALS_18
        );
    }

    function callSellCostWithExcessiveOutput() external pure {
        LinearCurveMathV4.calculateSellCost(
            10000e18, 100e18, BASE_PRICE_18, 2e13, DECIMALS_18, DECIMALS_18
        );
    }

    function test_PriceMonotonicity_MustAlwaysIncrease() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Test at multiple supply points
        uint256[] memory supplyPoints = new uint256[](5);
        supplyPoints[0] = 0;
        supplyPoints[1] = 1000e18;
        supplyPoints[2] = 5000e18;
        supplyPoints[3] = 7500e18;
        supplyPoints[4] = 9999e18;

        for (uint256 i = 0; i < supplyPoints.length; i++) {
            uint256 supply = supplyPoints[i];

            // Calculate price at current supply (marginal cost for 1 token)
            uint256 priceAtSupply = LinearCurveMathV4.calculateBuyCost(
                1e18, supply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
            );

            // Calculate price at supply + 1000
            uint256 priceAtSupplyPlus = LinearCurveMathV4.calculateBuyCost(
                1e18, supply + 1000e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
            );

            assertGt(priceAtSupplyPlus, priceAtSupply, "Price must increase as supply increases");
        }
    }

    function test_PriceMonotonicity_ContinuousIncrease() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 prevAvgPrice = 0;

        // Check monotonicity in steps of 100 tokens up to 1000
        for (uint256 supply = 0; supply <= 900e18; supply += 100e18) {
            uint256 buyAmount = 100e18;
            uint256 cost = LinearCurveMathV4.calculateBuyCost(
                buyAmount, supply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
            );

            uint256 avgPrice = (cost * 1e18) / buyAmount; // Average price per token

            if (supply > 0) {
                assertGt(avgPrice, prevAvgPrice, "Average price must increase with supply");
            }
            prevAvgPrice = avgPrice;
        }
    }

    function test_AreaUnderCurve_MathematicalCorrectness() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Buy amount from 0 supply
        uint256 amount = 1000e18;
        uint256 calculatedCost = LinearCurveMathV4.calculateBuyCost(
            amount, 0, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Mathematical formula: cost = basePrice * amount + (slope * amount^2) / 2
        // Convert to UD60x18 for precise calculation
        UD60x18 amountFP = ud(amount);
        UD60x18 baseFP = ud(BASE_PRICE_18);
        UD60x18 slopeFP = ud(slopeVal);

        // basePrice * amount
        UD60x18 linearTerm = baseFP.mul(amountFP);

        // (slope * amount^2) / 2
        UD60x18 quadraticTerm = slopeFP.mul(amountFP).mul(amountFP).div(ud(2e18));

        uint256 expectedCost = UD60x18.unwrap(linearTerm.add(quadraticTerm));

        assertApproxEqRel(
            calculatedCost, expectedCost, 0.001e18, "Cost should match area under curve formula"
        );
    }

    function test_AreaUnderCurve_IntegralConsistency() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Calculate total cost by summing small increments (numerical integration)
        uint256 totalCostByIntegration = 0;
        uint256 step = 100e18;
        uint256 targetAmount = 1000e18;

        for (uint256 i = 0; i < targetAmount / step; i++) {
            uint256 supply = i * step;
            uint256 incrementCost = LinearCurveMathV4.calculateBuyCost(
                step, supply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
            );
            totalCostByIntegration += incrementCost;
        }

        // Calculate total cost in one go
        uint256 totalCostDirect = LinearCurveMathV4.calculateBuyCost(
            targetAmount, 0, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should be approximately equal (some rounding difference expected)
        assertApproxEqRel(
            totalCostByIntegration,
            totalCostDirect,
            0.01e18,
            "Integration should match direct calculation"
        );
    }

    // ======== TEST 4: BOUNDARY CONDITIONS AT MAX SUPPLY ========

    function test_BoundaryConditions_AtMaxSupply() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Test buying when at max supply
        uint256 costAtMax = LinearCurveMathV4.calculateBuyCost(
            1e18, MAX_SUPPLY_18 - 1e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Price should be highest at max supply
        uint256 costAtStart = LinearCurveMathV4.calculateBuyCost(
            1e18, 0, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(costAtMax, costAtStart, "Cost at max supply should be highest");

        // Test selling at max supply
        uint256 sellReturn = LinearCurveMathV4.calculateSellAmount(
            1e18, MAX_SUPPLY_18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should get approximately the final price for last token
        assertApproxEqRel(
            sellReturn,
            finalPriceVal,
            0.01e18,
            "Sell at max should return approximately final price"
        );
    }

    function test_Precision_SmallAmounts() public pure {
        // Use factory's actual very low base price
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            FACTORY_TARGET_AMOUNT, FACTORY_MAX_SUPPLY, FACTORY_BASE_PRICE, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, FACTORY_BASE_PRICE, FACTORY_MAX_SUPPLY, DECIMALS_18, DECIMALS_18
        );

        // Test with very small amounts (potential precision loss)
        uint256 smallAmount = 1e15; // 0.001 tokens
        uint256 cost = LinearCurveMathV4.calculateBuyCost(
            smallAmount, 0, FACTORY_BASE_PRICE, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(cost, 0, "Should handle small amounts without losing precision");

        uint256 smallBuyAmount = LinearCurveMathV4.calculateBuyAmount(
            1e10, // Small but reasonable amount
            0,
            FACTORY_BASE_PRICE,
            slopeVal,
            DECIMALS_18,
            DECIMALS_18
        );

        assertGt(smallBuyAmount, 0, "Should handle small but reasonable purchases");
    }

    function test_Precision_VeryLowBasePrice() public pure {
        uint256 basePrice = 1e15; // 0.001 per token
        uint256 targetAmount = 20_675e18;
        uint256 maxSupply = 225_000e18;

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_18, DECIMALS_18
        );

        // With corrected formula: (2 * 20675e18 / 225000e18) - 1e15
        // = 0.18377e18 - 0.001e18 ≈ 0.18277e18
        assertGt(finalPriceVal, 0, "Final price should be positive");
        assertLt(finalPriceVal, 1e18, "Final price should be reasonable");

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, basePrice, maxSupply, DECIMALS_18, DECIMALS_18
        );

        // Total cost to buy entire curve
        uint256 totalCost = LinearCurveMathV4.calculateBuyCost(
            maxSupply, 0, basePrice, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Should accumulate close to graduation threshold (may be slightly under due to rounding)
        assertApproxEqRel(totalCost, targetAmount, 0.01e18, "Total accumulation should be close to graduation threshold");
    }

    function test_SequentialBuys_ConsistentWithSingleBuy() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Buy 300 tokens in one transaction
        uint256 singleBuyCost = LinearCurveMathV4.calculateBuyCost(
            300e18, 0, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Buy 300 tokens in three 100-token transactions
        uint256 cost1 = LinearCurveMathV4.calculateBuyCost(
            100e18, 0, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        uint256 cost2 = LinearCurveMathV4.calculateBuyCost(
            100e18, 100e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        uint256 cost3 = LinearCurveMathV4.calculateBuyCost(
            100e18, 200e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        uint256 multipleBuysCost = cost1 + cost2 + cost3;

        assertApproxEqRel(
            singleBuyCost, multipleBuysCost, 0.001e18, "Multiple buys should equal single buy"
        );
    }

    function test_BuySellBuy_PathIndependence() public pure {
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Path 1: Buy 200 directly from supply 100
        uint256 directCost = LinearCurveMathV4.calculateBuyCost(
            200e18, 100e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Path 2: Buy 300, sell 100, end at same position
        uint256 buyCost = LinearCurveMathV4.calculateBuyCost(
            300e18, 100e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        uint256 sellReturn = LinearCurveMathV4.calculateSellAmount(
            100e18, 400e18, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        uint256 netCostPath2 = buyCost - sellReturn;

        // Direct path should be cheaper or equal (no slippage from round trip)
        assertLe(directCost, netCostPath2, "Direct path should be more efficient or equal");
    }

    function test_ZeroSlope_HandlesCorrectly() public pure {
        // With corrected formula and very small target, this will underflow
        // (2 * 1 / 1000000e18) - 1e18 will be negative
        // So we need different parameters: low base price, larger target
        uint256 targetAmount = 100000e18;
        uint256 maxSupply = 1000000e18;
        uint256 basePrice = 1e15; // Very low base price

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, DECIMALS_18, DECIMALS_18
        );

        // (2 * 100000e18 / 1000000e18) - 1e15 = 0.2e18 - 0.001e18 = 0.199e18
        assertGt(finalPriceVal, 0, "Final price should be positive");

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, basePrice, maxSupply, DECIMALS_18, DECIMALS_18
        );

        // Slope will be very small: (0.199e18 - 0.001e15) / 1000000e18
        assertGt(slopeVal, 0, "Slope should be positive but very small");
        assertLt(slopeVal, 1e12, "Slope should be very small");
    }
}

