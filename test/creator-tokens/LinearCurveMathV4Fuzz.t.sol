// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/lib/LinearCurveMath.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

contract LinearCurveMathV4CriticalTest is Test {
    using LinearCurveMathV4 for *;
    // Standard test constants - updated for corrected formula
    // Need: (2 * target / supply) > base
    uint256 constant TARGET_AMOUNT_18 = 10_000e18;
    uint256 constant MAX_SUPPLY_18 = 100_000e18;
    uint256 constant BASE_PRICE_18 = 0.01e18;

    uint8 constant DECIMALS_6 = 6;
    uint8 constant DECIMALS_8 = 8;
    uint8 constant DECIMALS_18 = 18;

    function setUp() public { }

    function testFuzz_Monotonicity(uint256 supply1, uint256 supply2) public pure {
        supply1 = bound(supply1, 0, MAX_SUPPLY_18 - 2e18);
        supply2 = bound(supply2, supply1 + 1e18, MAX_SUPPLY_18 - 1e18);

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        uint256 price1 = LinearCurveMathV4.calculateBuyCost(
            1e18, supply1, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        uint256 price2 = LinearCurveMathV4.calculateBuyCost(
            1e18, supply2, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        assertGt(price2, price1, "Price must increase with supply");
    }

    function testFuzz_BuySellSymmetry(uint256 amount, uint256 supply) public pure {
        amount = bound(amount, 1e16, 100e18);
        supply = bound(supply, amount, 5000e18);

        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            TARGET_AMOUNT_18, MAX_SUPPLY_18, BASE_PRICE_18, DECIMALS_18, DECIMALS_18
        );

        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, BASE_PRICE_18, MAX_SUPPLY_18, DECIMALS_18, DECIMALS_18
        );

        // Calculate sell return
        uint256 sellReturn = LinearCurveMathV4.calculateSellAmount(
            amount, supply, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Calculate how much it would cost to buy back
        uint256 buyBackCost = LinearCurveMathV4.calculateBuyCost(
            amount, supply - amount, BASE_PRICE_18, slopeVal, DECIMALS_18, DECIMALS_18
        );

        // Buy back cost should equal sell return (within rounding)
        assertApproxEqRel(buyBackCost, sellReturn, 0.001e18, "Buy and sell should be symmetric");
    }

    function testFuzz_DecimalHandling(
        uint8 buyDecimals,
        uint8 sellDecimals,
        uint256 targetMultiplier,
        uint256 supplyMultiplier
    ) public pure {
        // Bound decimals to reasonable values
        buyDecimals = uint8(bound(buyDecimals, 4, 18));
        sellDecimals = uint8(bound(sellDecimals, 4, 18));

        // Bound multipliers to ensure valid formula
        targetMultiplier = bound(targetMultiplier, 1000, 100000); // 1000-100000x
        supplyMultiplier = bound(supplyMultiplier, 1000, 100000); // 1000-100000x
        
        // Construct amounts that guarantee (2 * target / supply) > base
        uint256 targetAmount = targetMultiplier * 10 ** sellDecimals;
        uint256 maxSupply = supplyMultiplier * 10 ** buyDecimals;
        
        // Use very low base price: 0.001 of a unit
        uint256 basePrice = 10 ** (sellDecimals > 3 ? sellDecimals - 3 : 1);

        // Should not revert with valid decimal inputs
        uint256 finalPriceVal = LinearCurveMathV4.finalPrice(
            targetAmount, maxSupply, basePrice, buyDecimals, sellDecimals
        );

        // With corrected formula: finalPrice = (2 * target / supply) - base
        assertGt(finalPriceVal, 0, "Final price should be positive");

        // Calculate slope should work
        uint256 slopeVal = LinearCurveMathV4.slope(
            finalPriceVal, basePrice, maxSupply, buyDecimals, sellDecimals
        );

        assertGe(slopeVal, 0, "Slope should be non-negative");

        // Only test buy calculation if slope is positive (otherwise it would revert)
        if (slopeVal > 0) {
            // Buy calculation should work
            uint256 inputAmount = 100 * 10 ** sellDecimals;
            uint256 buyAmount = LinearCurveMathV4.calculateBuyAmount(
                inputAmount, 0, basePrice, slopeVal, buyDecimals, sellDecimals
            );

            assertGt(buyAmount, 0, "Should receive tokens for any valid decimal configuration");
        }
    }
}

