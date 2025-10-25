// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AntiFlipFeeBase
 * @author Fleek
 * @notice Abstract base contract providing shared anti-flip fee logic for both bonding curve and Uniswap V4 phases
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
 *
 * Implementation Notes
 * ====================
 * - Each implementing contract maintains its own userLastBuy mapping
 * - BondingCurve and Hook have independent tracking (no migration at graduation)
 * - entropyTimestamp differs: deploymentTimestamp (curve) vs graduationTimestamp (hook)
 */
abstract contract AntiFlipFeeBase {
    uint256 public constant BASE_FEE_BPS = 200;
    uint256 public constant SNIPE_PENALTY_BPS = 1000;
    uint256 public constant MAX_TOTAL_FEE_BPS = 1200;
    uint256 public constant MIN_WINDOW = 30;
    uint256 public constant WINDOW_RANGE = 91;

    address public immutable CREATOR_TOKEN;
    address public immutable CREATOR;
    address public immutable VESTING_WALLET;

    mapping(address => uint256) public userLastBuy;

    constructor(address _creator, address _creatorToken, address _vestingWallet) {
        CREATOR = _creator;
        CREATOR_TOKEN = _creatorToken;
        VESTING_WALLET = _vestingWallet;
    }

    function _getEntropyTimestamp() internal view virtual returns (uint256);

    function calculateWindow(address user, uint256 buyTimestamp) public view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(user, CREATOR_TOKEN, buyTimestamp, _getEntropyTimestamp())
            )
        );

        return MIN_WINDOW + (seed % WINDOW_RANGE);
    }

    function getTotalFee(address user, bool isBuy) public view returns (uint256 feePercent) {
        uint256 totalFee = BASE_FEE_BPS;

        if (!isBuy) {
            uint256 lastBuyTime = userLastBuy[user];

            if (lastBuyTime > 0) {
                uint256 windowDuration = calculateWindow(user, lastBuyTime);
                uint256 elapsed = block.timestamp - lastBuyTime;

                if (elapsed < windowDuration) {
                    totalFee += SNIPE_PENALTY_BPS;
                }
            }
        }

        return totalFee;
    }

    function _getFeeRates() internal view returns (uint256 foundationBps, uint256 creatorBps) {
        uint256 creatorBalance = IERC20(CREATOR_TOKEN).balanceOf(CREATOR);
        uint256 vestingBalance = IERC20(CREATOR_TOKEN).balanceOf(VESTING_WALLET);
        uint256 totalHeld = creatorBalance + vestingBalance;

        if (totalHeld >= 250_000e18) return (150, 50);
        if (totalHeld >= 150_000e18) return (160, 40);
        if (totalHeld >= 50_000e18) return (170, 30);
        return (175, 25);
    }

    function _calculateFees(uint256 amount, address user, bool isBuy)
        internal
        view
        returns (uint256 totalFee, uint256 foundationFee, uint256 creatorFee)
    {
        uint256 totalFeeBps = getTotalFee(user, isBuy);
        totalFee = (amount * totalFeeBps) / 10000;

        if (totalFee == 0) return (0, 0, 0);

        (uint256 foundationBps, uint256 creatorBps) = _getFeeRates();
        foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
        creatorFee = totalFee - foundationFee;
    }
}
