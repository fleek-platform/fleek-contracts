// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Config } from "./Config.sol";

/**
 * @title AntiFlipFeeLib
 * @author Fleek
 * @notice Library providing shared anti-flip fee calculation logic
 *
 * Fee Structure
 * =============
 * Base Fee: 2% on all trades (always applied to FLK)
 * Snipe Penalty: Additional 10% on sells within personalized time window
 * Maximum Total: 12% (base + penalty)
 *
 * Fee Distribution
 * ================
 * Dynamic split based on creator's token holdings:
 *   Creator holds ≥250k: Foundation 75%, Creator 25%
 *   Creator holds ≥150k: Foundation 80%, Creator 20%
 *   Creator holds ≥50k: Foundation 85%, Creator 15%
 *   Creator holds <50k: Foundation 87.5%, Creator 12.5%
 *
 * Anti-Snipe Mechanism
 * ====================
 * Window duration: 30-120 seconds, deterministic per user but unpredictable until buy executes
 * Entropy: keccak256(user, token, buyTimestamp, entropyTimestamp)
 * Window resets on every subsequent buy, preventing "buy once flip forever" strategies
 */
library AntiFlipFeeLib {
    uint256 internal constant BASE_FEE_BPS = 200;
    uint256 internal constant SNIPE_PENALTY_BPS = 1000;
    uint256 internal constant MAX_TOTAL_FEE_BPS = 1200;
    uint256 internal constant MIN_WINDOW = 30;
    uint256 internal constant WINDOW_RANGE = 91;

    function calculateWindow(
        address user,
        address creatorToken,
        uint256 buyTimestamp,
        uint256 entropyTimestamp
    ) internal pure returns (uint256) {
        uint256 seed = uint256(
            keccak256(abi.encodePacked(user, creatorToken, buyTimestamp, entropyTimestamp))
        );

        return MIN_WINDOW + (seed % WINDOW_RANGE);
    }

    function getTotalFee(
        address user,
        bool isBuy,
        mapping(address => uint256) storage userLastBuy,
        address creatorToken,
        uint256 entropyTimestamp
    ) internal view returns (uint256 feePercent) {
        uint256 totalFee = BASE_FEE_BPS;

        if (!isBuy) {
            uint256 lastBuyTime = userLastBuy[user];

            if (lastBuyTime > 0) {
                uint256 windowDuration =
                    calculateWindow(user, creatorToken, lastBuyTime, entropyTimestamp);
                uint256 elapsed = block.timestamp - lastBuyTime;

                if (elapsed < windowDuration) {
                    totalFee += SNIPE_PENALTY_BPS;
                }
            }
        }

        return totalFee;
    }

    function getFeeRates(address creator, address creatorToken, address vestingWallet)
        internal
        view
        returns (uint256 foundationBps, uint256 creatorBps)
    {
        uint256 creatorBalance = IERC20(creatorToken).balanceOf(creator);
        uint256 vestingBalance = IERC20(creatorToken).balanceOf(vestingWallet);
        uint256 totalHeld = creatorBalance + vestingBalance;

        if (totalHeld >= Config.FEE_TIER_1) return (150, 50);
        if (totalHeld >= Config.FEE_TIER_2) return (160, 40);
        if (totalHeld >= Config.FEE_TIER_3) return (170, 30);
        return (175, 25);
    }

    function calculateFees(
        uint256 amount,
        address user,
        bool isBuy,
        mapping(address => uint256) storage userLastBuy,
        address creator,
        address creatorToken,
        address vestingWallet,
        uint256 entropyTimestamp
    ) internal view returns (uint256 totalFee, uint256 foundationFee, uint256 creatorFee) {
        uint256 totalFeeBps = getTotalFee(user, isBuy, userLastBuy, creatorToken, entropyTimestamp);
        totalFee = (amount * totalFeeBps) / 10000;

        if (totalFee == 0) return (0, 0, 0);

        (uint256 foundationBps, uint256 creatorBps) =
            getFeeRates(creator, creatorToken, vestingWallet);
        foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
        creatorFee = totalFee - foundationFee;
    }
}
