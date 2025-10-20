// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { UD60x18, ud, convert } from "@prb/math/src/UD60x18.sol";

/**
 * @title LinearCurveMathV4
 * @notice Multi-decimal linear bonding curve math library using PRB Math for enhanced precision and safety
 * @dev This library uses UD60x18 fixed-point arithmetic internally while supporting any decimal precision
 */
library LinearCurveMathV4 {
    error InvalidTargetAmount();
    error InvalidMaxSupply();
    error InvalidDecimals();
    error FinalPriceBelowBase();
    error InvalidSlope();
    error InvalidInputAmount();
    error OutputTooSmall();
    error InsufficientLiquidity();

    /**
     * @notice Calculates the final price at graduation threshold
     * @dev Formula: finalPrice = (2 * targetAmount / maxSupply) + basePrice
     * @param targetAmount Amount of sell tokens to accumulate for graduation
     * @param maxSupply Maximum supply of buy tokens
     * @param basePrice Base price per buy token (in sell token terms)
     * @param buyTokenDecimals Decimals of the buy token
     * @param sellTokenDecimals Decimals of the sell token
     * @return finalPrice The price at graduation in sell token decimals
     */
    function finalPrice(
        uint256 targetAmount,
        uint256 maxSupply,
        uint256 basePrice,
        uint8 buyTokenDecimals,
        uint8 sellTokenDecimals
    ) internal pure returns (uint256) {
        if (targetAmount == 0) revert InvalidTargetAmount();
        if (maxSupply == 0) revert InvalidMaxSupply();
        if (buyTokenDecimals > 18 || sellTokenDecimals > 18) revert InvalidDecimals();

        // Convert to UD60x18 for safe math operations
        UD60x18 targetFP = _toUD60x18(targetAmount, sellTokenDecimals);
        UD60x18 maxSupplyFP = _toUD60x18(maxSupply, buyTokenDecimals);
        UD60x18 baseFP = _toUD60x18(basePrice, sellTokenDecimals);
        UD60x18 two = ud(2e18);

        // Calculate: (2 * targetAmount / maxSupply) + basePrice
        UD60x18 result = two.mul(targetFP).div(maxSupplyFP).add(baseFP);

        return _fromUD60x18(result, sellTokenDecimals);
    }

    /**
     * @notice Calculates the slope of the linear bonding curve
     * @dev Formula: slope = (finalPrice - basePrice) / maxSupply
     * @param _finalPrice Final price at graduation (in sell token decimals)
     * @param basePrice Base price per buy token (in sell token decimals)
     * @param maxSupply Maximum supply of buy tokens (in buy token decimals)
     * @param buyTokenDecimals Decimals of the buy token
     * @param sellTokenDecimals Decimals of the sell token
     * @return slope The slope with 18 decimal precision (internal format)
     */
    function slope(
        uint256 _finalPrice,
        uint256 basePrice,
        uint256 maxSupply,
        uint8 buyTokenDecimals,
        uint8 sellTokenDecimals
    ) internal pure returns (uint256) {
        UD60x18 finalFP = _toUD60x18(_finalPrice, sellTokenDecimals);
        UD60x18 baseFP = _toUD60x18(basePrice, sellTokenDecimals);
        UD60x18 maxSupplyFP = _toUD60x18(maxSupply, buyTokenDecimals);

        if (finalFP.lt(baseFP)) revert FinalPriceBelowBase();
        if (maxSupply == 0) revert InvalidMaxSupply();

        // Calculate: (finalPrice - basePrice) / maxSupply
        UD60x18 result = finalFP.sub(baseFP).div(maxSupplyFP);

        // Return as raw UD60x18 value (18 decimal internal precision)
        return UD60x18.unwrap(result);
    }

    /**
     * @notice Calculates buy amount using quadratic formula for linear bonding curve
     * @dev Solves: inputAmount = (basePrice + slope * accumulated) * outputAmount + (slope * outputAmount^2) / 2
     * @param inputAmount Amount of sell tokens to spend
     * @param currentAccumulated Currently accumulated sell tokens
     * @param basePrice Base price per buy token (in sell token decimals)
     * @param slopeValue Slope of the bonding curve (18 decimal internal format)
     * @param buyTokenDecimals Decimals of the buy token
     * @param sellTokenDecimals Decimals of the sell token
     * @return buyAmount Amount of buy tokens to receive
     */
    function calculateBuyAmount(
        uint256 inputAmount,
        uint256 currentAccumulated,
        uint256 basePrice,
        uint256 slopeValue,
        uint8 buyTokenDecimals,
        uint8 sellTokenDecimals
    ) internal pure returns (uint256) {
        if (slopeValue == 0) revert InvalidSlope();
        if (inputAmount == 0) revert InvalidInputAmount();

        // Special case: if accumulated is 0, use simple linear approximation
        if (currentAccumulated == 0) {
            UD60x18 sellAmountFP = _toUD60x18(inputAmount, sellTokenDecimals);
            UD60x18 basePriceFP = _toUD60x18(basePrice, sellTokenDecimals);

            // Simple: outputAmount ≈ inputAmount / basePrice for small amounts
            UD60x18 buyAmountFP = sellAmountFP.div(basePriceFP);

            if (UD60x18.unwrap(buyAmountFP) == 0) revert OutputTooSmall();
            return _fromUD60x18(buyAmountFP, buyTokenDecimals);
        }

        // Convert to UD60x18 for calculations
        UD60x18 inputFP = _toUD60x18(inputAmount, sellTokenDecimals);
        UD60x18 accumulatedFP = _toUD60x18(currentAccumulated, sellTokenDecimals);
        UD60x18 baseFP = _toUD60x18(basePrice, sellTokenDecimals);
        UD60x18 slopeFP = UD60x18.wrap(slopeValue);

        // Quadratic formula: ax^2 + bx - c = 0
        UD60x18 a = slopeFP.div(ud(2e18));
        UD60x18 b = baseFP.add(slopeFP.mul(accumulatedFP));

        // Calculate discriminant: b^2 + 4ac
        UD60x18 discriminant = b.mul(b).add(ud(4e18).mul(a).mul(inputFP));

        // Solution: x = (sqrt(discriminant) - b) / (2a)
        UD60x18 outputFP = discriminant.sqrt().sub(b).div(ud(2e18).mul(a));

        if (UD60x18.unwrap(outputFP) == 0) revert OutputTooSmall();

        return _fromUD60x18(outputFP, buyTokenDecimals);
    }

    /**
     * @notice Calculates sell amount for linear bonding curve
     * @dev Uses average price over the selling range
     * @param inputAmount Amount of buy tokens to sell
     * @param currentAccumulated Currently accumulated sell tokens
     * @param basePrice Base price per buy token (in sell token decimals)
     * @param slopeValue Slope of the bonding curve (18 decimal internal format)
     * @param buyTokenDecimals Decimals of the buy token
     * @param sellTokenDecimals Decimals of the sell token
     * @return sellAmount Amount of sell tokens to receive
     */
    function calculateSellAmount(
        uint256 inputAmount,
        uint256 currentAccumulated,
        uint256 basePrice,
        uint256 slopeValue,
        uint8 buyTokenDecimals,
        uint8 sellTokenDecimals
    ) internal pure returns (uint256) {
        if (inputAmount == 0) revert InvalidInputAmount();
        if (currentAccumulated == 0) revert InsufficientLiquidity(); // Can't sell when nothing accumulated

        // Convert to UD60x18
        UD60x18 inputFP = _toUD60x18(inputAmount, buyTokenDecimals);
        UD60x18 accumulatedFP = _toUD60x18(currentAccumulated, sellTokenDecimals);
        UD60x18 baseFP = _toUD60x18(basePrice, sellTokenDecimals);
        UD60x18 slopeFP = UD60x18.wrap(slopeValue);

        // Convert input amount to sell token decimals for comparison
        UD60x18 inputInSellDecimals =
            inputFP.mul(_toUD60x18(basePrice, sellTokenDecimals)).div(ud(1e18));

        // Check if we have enough to sell
        if (inputInSellDecimals.gt(accumulatedFP)) revert InsufficientLiquidity();

        // Calculate average price over selling range
        UD60x18 startPrice = baseFP.add(slopeFP.mul(accumulatedFP));
        UD60x18 endPrice = baseFP.add(slopeFP.mul(accumulatedFP.sub(inputInSellDecimals)));
        UD60x18 outputFP = inputFP.mul(startPrice.add(endPrice).div(ud(2e18)));

        if (outputFP.gt(accumulatedFP)) revert InsufficientLiquidity();

        return _fromUD60x18(outputFP, sellTokenDecimals);
    }

    /**
     * @notice Calculates cost to buy exact amount of tokens
     * @dev Inverse of calculateBuyAmount
     * Formula: cost = basePrice * amount + slope * accumulated * amount + (slope * amount^2) / 2
     */
    function calculateBuyCost(
        uint256 outputAmount,
        uint256 currentAccumulated,
        uint256 basePrice,
        uint256 slopeValue,
        uint8 buyTokenDecimals,
        uint8 sellTokenDecimals
    ) internal pure returns (uint256) {
        if (outputAmount == 0) revert InvalidInputAmount();

        // Special case for zero accumulated
        if (currentAccumulated == 0) {
            UD60x18 buyAmountFP = _toUD60x18(outputAmount, buyTokenDecimals);
            UD60x18 basePriceFP = _toUD60x18(basePrice, sellTokenDecimals);

            return _fromUD60x18(buyAmountFP.mul(basePriceFP), sellTokenDecimals);
        }

        UD60x18 outputFP = _toUD60x18(outputAmount, buyTokenDecimals);
        UD60x18 accumulatedFP = _toUD60x18(currentAccumulated, sellTokenDecimals);
        UD60x18 baseFP = _toUD60x18(basePrice, sellTokenDecimals);
        UD60x18 slopeFP = UD60x18.wrap(slopeValue);

        // Average price calculation for the range
        UD60x18 startPrice = baseFP.add(slopeFP.mul(accumulatedFP));
        UD60x18 endPrice = baseFP.add(slopeFP.mul(accumulatedFP.add(outputFP)));
        UD60x18 avgPrice = startPrice.add(endPrice).div(ud(2e18));

        UD60x18 costFP = outputFP.mul(avgPrice);

        return _fromUD60x18(costFP, sellTokenDecimals);
    }

    /**
     * @notice Calculates tokens needed to sell for exact sell token output
     * @dev Inverse of calculateSellAmount - finds how many buy tokens to sell for desired sell token output
     */
    function calculateSellCost(
        uint256 outputAmount,
        uint256 currentAccumulated,
        uint256 basePrice,
        uint256 slopeValue,
        uint8 buyTokenDecimals,
        uint8 sellTokenDecimals
    ) internal pure returns (uint256) {
        if (outputAmount == 0) revert InvalidInputAmount();
        if (outputAmount > currentAccumulated) revert InsufficientLiquidity();
        if (currentAccumulated == 0) revert InsufficientLiquidity(); // Can't sell from zero

        UD60x18 outputFP = _toUD60x18(outputAmount, sellTokenDecimals);
        UD60x18 accumulatedFP = _toUD60x18(currentAccumulated, sellTokenDecimals);
        UD60x18 baseFP = _toUD60x18(basePrice, sellTokenDecimals);
        UD60x18 slopeFP = UD60x18.wrap(slopeValue);

        // Need to solve: outputAmount = inputAmount * avgPrice
        // where avgPrice = (startPrice + endPrice) / 2
        // startPrice = base + slope * accumulated
        // endPrice = base + slope * (accumulated - inputAmount)

        // This simplifies to a quadratic equation
        UD60x18 two = ud(2e18);
        UD60x18 a = slopeFP.div(two);
        UD60x18 b = baseFP.add(slopeFP.mul(accumulatedFP)).sub(a);

        // Quadratic: a*x^2 - b*x + output = 0
        // x = (b ± sqrt(b^2 - 4*a*output)) / (2*a)
        UD60x18 discriminant = b.mul(b).sub(ud(4e18).mul(a).mul(outputFP));

        // We want the smaller root (positive amount that gives us the output)
        UD60x18 inputFP = b.sub(discriminant.sqrt()).div(two.mul(a));

        return _fromUD60x18(inputFP, buyTokenDecimals);
    }

    /**
     * @notice Converts a token amount to UD60x18 fixed-point format
     * @param amount The amount in token's native decimals
     * @param tokenDecimals Number of decimals the token uses
     * @return The amount as a UD60x18 fixed-point number
     */
    function _toUD60x18(uint256 amount, uint8 tokenDecimals) private pure returns (UD60x18) {
        if (tokenDecimals == 18) {
            return UD60x18.wrap(amount);
        } else if (tokenDecimals < 18) {
            return UD60x18.wrap(amount * 10 ** (18 - tokenDecimals));
        } else {
            return UD60x18.wrap(amount / 10 ** (tokenDecimals - 18));
        }
    }

    /**
     * @notice Converts a UD60x18 fixed-point number back to token's native decimals
     * @param amount The UD60x18 fixed-point number
     * @param tokenDecimals Number of decimals for the target token
     * @return The amount in token's native decimals
     */
    function _fromUD60x18(UD60x18 amount, uint8 tokenDecimals) private pure returns (uint256) {
        uint256 rawAmount = UD60x18.unwrap(amount);

        if (tokenDecimals == 18) {
            return rawAmount;
        } else if (tokenDecimals < 18) {
            return rawAmount / 10 ** (18 - tokenDecimals);
        } else {
            return rawAmount * 10 ** (tokenDecimals - 18);
        }
    }

    /**
     * @notice Helper function to convert a price from one token decimal to another
     * @param price Price in fromDecimals format
     * @param fromDecimals Current decimal precision
     * @param toDecimals Target decimal precision
     * @return The price in toDecimals format
     */
    function convertPrice(uint256 price, uint8 fromDecimals, uint8 toDecimals)
        external
        pure
        returns (uint256)
    {
        if (fromDecimals == toDecimals) {
            return price;
        } else if (fromDecimals < toDecimals) {
            return price * 10 ** (toDecimals - fromDecimals);
        } else {
            return price / 10 ** (fromDecimals - toDecimals);
        }
    }
}
