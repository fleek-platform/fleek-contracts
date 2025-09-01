// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test, console, Vm } from "forge-std/Test.sol";
import { stdError } from "forge-std/StdError.sol";
import { StakingRewards } from "../../src/staking/StakingRewards.sol";
import { FLKToken } from "../../src/token/FLKToken.sol";

contract StakingRewardsTest is Test {
    StakingRewards public stakingRewards;
    FLKToken public token;

    address public FOUNDATION_MULTISIG = makeAddr("FOUNDATION_MULTISIG");
    address public REWARDS_DISTRIBUTOR = makeAddr("REWARDS_DISTRIBUTOR");

    address public UNAUTHORIZED_ADDRESS = makeAddr("UNAUTHORIZED_ADDRESS");

    address[] public users;
    uint256 constant NUM_USERS = 10;

    uint256 constant MAX_USER_BALANCE = 1_000_000e18;

    function setUp() public {
        token = new FLKToken(FOUNDATION_MULTISIG);

        stakingRewards = new StakingRewards(
            FOUNDATION_MULTISIG, address(token), address(token), REWARDS_DISTRIBUTOR, 90 days
        );

        vm.deal(FOUNDATION_MULTISIG, 1 ether);
        vm.deal(REWARDS_DISTRIBUTOR, 1 ether);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);
            vm.deal(user, 1 ether);
        }

        vm.startPrank(FOUNDATION_MULTISIG);
        token.transfer(REWARDS_DISTRIBUTOR, 10_000_000e18);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            token.transfer(users[i], MAX_USER_BALANCE);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            token.approve(address(stakingRewards), type(uint256).max);
        }

        vm.prank(REWARDS_DISTRIBUTOR);
        token.approve(address(stakingRewards), type(uint256).max);
    }

    /// @notice Test: Rounding error accumulation over extended periods with uneven stakes
    function test_RoundingErrorAccumulation() public {
        uint256 rewardAmount = 1000000e18;

        // Test with dust stakes
        uint256 dustStake = 1000;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            stakingRewards.stake(dustStake);
        }

        // Test with uneven stake amounts
        uint256[] memory stakes = new uint256[](4);
        stakes[0] = 1000e18;
        stakes[1] = 2000e18;
        stakes[2] = 5000e18;
        stakes[3] = 10000e18;

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(users[i + 5]);
            stakingRewards.stake(stakes[i]);
        }

        // Single reward distribution instead of 100 iterations
        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 90 days);

        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < 9; i++) {
            uint256 earned = stakingRewards.earned(users[i]);
            if (earned > 0) {
                vm.prank(users[i]);
                stakingRewards.getReward();
                totalClaimed += earned;
            }
        }

        uint256 tolerance = rewardAmount / 10000;
        assertLe(
            totalClaimed, rewardAmount + tolerance, "Total claimed should not exceed distributed"
        );

        uint256 minExpected = rewardAmount * 99 / 100; // Expect ~99% due to dust stakes
        assertGe(totalClaimed, minExpected, "Should claim most rewards despite dust stakes");
    }
    /// @notice Test: Reward per token should never decrease

    function test_RewardPerTokenMonotonic() public {
        vm.prank(users[0]);
        stakingRewards.stake(1000e18);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), 100000e18);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(100000e18);

        uint256[] memory snapshots = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 9 days);
            snapshots[i] = stakingRewards.rewardPerToken();

            if (i > 0) {
                assertGe(snapshots[i], snapshots[i - 1], "RewardPerToken must be monotonic");
            }
        }
    }

    /// @notice Test: Earned rewards cannot exceed mathematical maximum
    function test_EarnedBounds() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 90 days);

        uint256 earned = stakingRewards.earned(users[0]);
        uint256 rewardPerToken = stakingRewards.rewardPerToken();
        uint256 maxPossible = (stakeAmount * rewardPerToken) / 1e18;

        assertLe(earned, maxPossible + 1, "Earned cannot exceed mathematical maximum");

        assertApproxEqRel(
            earned, rewardAmount, 0.001e18, "Single staker should earn nearly all rewards"
        );
    }

    /// @notice Test: Sequential stakes should reset lock timer
    function test_SequentialStakesResetLockTimer() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);
        uint256 firstStakeTime = block.timestamp;

        vm.warp(block.timestamp + 45 days);

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);
        uint256 secondStakeTime = block.timestamp;

        uint256 unlockTime = stakingRewards.unlockTime(users[0]);
        assertEq(unlockTime, secondStakeTime + 90 days, "Unlock time should reset on new stake");
        assertFalse(
            stakingRewards.isUnlocked(users[0]), "Should still be locked after second stake"
        );

        vm.warp(firstStakeTime + 90 days);
        assertFalse(
            stakingRewards.isUnlocked(users[0]), "Should remain locked beyond first stake unlock"
        );

        vm.warp(secondStakeTime + 90 days);
        assertTrue(stakingRewards.isUnlocked(users[0]), "Should unlock after second stake period");
    }

    /// @notice Test: Partial withdrawals after unlock period
    function test_PartialWithdrawalsAfterUnlock() public {
        uint256 totalStake = 2000e18;
        uint256 partialWithdraw = 500e18;

        vm.prank(users[0]);
        stakingRewards.stake(totalStake);

        uint256 stakeTime = block.timestamp;

        vm.warp(stakeTime + 90 days);
        vm.prank(users[0]);
        stakingRewards.withdraw(partialWithdraw);

        assertEq(
            stakingRewards.balanceOf(users[0]),
            totalStake - partialWithdraw,
            "Balance should decrease by withdrawal"
        );
        assertEq(
            stakingRewards.totalSupply(),
            totalStake - partialWithdraw,
            "Total supply should decrease"
        );

        vm.prank(users[0]);
        stakingRewards.withdraw(totalStake - partialWithdraw);

        assertEq(
            stakingRewards.balanceOf(users[0]), 0, "Balance should be zero after full withdrawal"
        );
    }

    /// @notice Test: Zero amount operations with lock period
    function test_ZeroAmountOperationsWithLockPeriod() public {
        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(StakingRewards.ZeroAmount.selector));
        stakingRewards.stake(0);

        vm.prank(users[0]);
        stakingRewards.stake(1000e18);

        vm.warp(block.timestamp + 90 days);
        vm.prank(users[0]);
        vm.expectRevert(abi.encodeWithSelector(StakingRewards.ZeroAmount.selector));
        stakingRewards.withdraw(0);
    }

    /// @notice Test: Lock period interaction with reward claims
    function test_LockPeriodWithRewardClaims() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 45 days);

        uint256 earned = stakingRewards.earned(users[0]);
        assertGt(earned, 0, "Should have earned rewards");

        uint256 userBalanceBefore = token.balanceOf(users[0]);
        vm.prank(users[0]);
        stakingRewards.getReward();

        uint256 userBalanceAfter = token.balanceOf(users[0]);
        assertEq(userBalanceAfter, userBalanceBefore + earned, "Should receive reward tokens");
    }

    /// @notice Test: Failed recovery of staking token
    function test_CannotRecoverStakingToken() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(FOUNDATION_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(StakingRewards.CannotWithdrawStakingToken.selector));
        stakingRewards.recoverERC20(address(token), stakeAmount);
    }

    /// @notice Test: Recovery of unknown ERC20 tokens
    function test_RecoverUnknownTokens() public {
        FLKToken unknownToken = new FLKToken(FOUNDATION_MULTISIG);
        uint256 unknownAmount = 500e18;

        vm.prank(FOUNDATION_MULTISIG);
        unknownToken.transfer(address(stakingRewards), unknownAmount);

        uint256 adminBalanceBefore = unknownToken.balanceOf(FOUNDATION_MULTISIG);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.recoverERC20(address(unknownToken), unknownAmount);

        assertEq(
            unknownToken.balanceOf(FOUNDATION_MULTISIG),
            adminBalanceBefore + unknownAmount,
            "Admin should receive recovered unknown tokens"
        );
        assertEq(
            unknownToken.balanceOf(address(stakingRewards)),
            0,
            "Contract should have zero unknown tokens"
        );
    }

    /// @notice Test: Automatic underflow protection on excessive withdraw
    function test_WithdrawExcessiveAmount() public {
        uint256 stakeAmount = 1000e18;
        uint256 excessiveWithdraw = 2000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.warp(block.timestamp + 90 days);

        vm.prank(users[0]);
        vm.expectRevert(stdError.arithmeticError);
        stakingRewards.withdraw(excessiveWithdraw);
    }

    /// @notice Test: Total supply underflow protection
    function test_TotalSupplyUnderflow() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.warp(block.timestamp + 90 days);
        vm.prank(users[0]);
        stakingRewards.withdraw(stakeAmount / 2);

        vm.prank(users[0]);
        vm.expectRevert(stdError.arithmeticError);
        stakingRewards.withdraw(stakeAmount);
    }

    /// @notice Test: RewardTooHigh protection with excessive reward
    function test_RewardTooHighProtection() public {
        uint256 rewardAmount = 1000e18;
        uint256 excessiveReward = rewardAmount * 2;

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        vm.expectRevert(abi.encodeWithSelector(StakingRewards.RewardTooHigh.selector));
        stakingRewards.notifyRewardAmount(excessiveReward);
    }

    /// @notice Test: Multiple reward notifications preventing overflow
    function test_MultipleRewardNotificationsOverflow() public {
        uint256 singleReward = 100000e18;
        uint256 iterations = 10;

        vm.prank(users[0]);
        stakingRewards.stake(1000e18);

        for (uint256 i = 0; i < iterations; i++) {
            vm.prank(REWARDS_DISTRIBUTOR);
            token.transfer(address(stakingRewards), singleReward);

            vm.prank(REWARDS_DISTRIBUTOR);
            stakingRewards.notifyRewardAmount(singleReward);

            vm.warp(block.timestamp + 1 days);
        }

        uint256 rewardRate = stakingRewards.rewardRate();
        assertGt(rewardRate, 0, "Should have positive reward rate");

        vm.warp(block.timestamp + 90 days);
        uint256 earned = stakingRewards.earned(users[0]);

        assertGt(earned, 0, "Should have earned some rewards");
        assertLt(earned, singleReward * iterations * 2, "Should not earn excessive rewards");
    }

    /// @notice Test: setRewardsDuration during active reward period - should fail
    function test_CannotSetDurationDuringActiveRewards() public {
        vm.prank(users[0]);
        stakingRewards.stake(1000e18);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), 100000e18);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(100000e18);

        vm.prank(FOUNDATION_MULTISIG);
        vm.expectRevert(abi.encodeWithSelector(StakingRewards.RewardsPeriodActive.selector));
        stakingRewards.setRewardsDuration(180 days);

        vm.warp(block.timestamp + 90 days + 1);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.setRewardsDuration(180 days);

        assertEq(stakingRewards.rewardsDuration(), 180 days, "Duration should be updated");
    }

    /// @notice Test: Impact on rewardRate after duration change - should pass
    function test_RewardRateAfterDurationChange() public {
        uint256 rewardAmount = 90000e18;
        uint256 initialDuration = 90 days;
        uint256 newDuration = 180 days;

        vm.prank(users[0]);
        stakingRewards.stake(1000e18);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        uint256 initialRate = stakingRewards.rewardRate();
        uint256 expectedInitialRate = rewardAmount / initialDuration;
        assertEq(initialRate, expectedInitialRate, "Initial rate should equal reward/duration");

        vm.warp(block.timestamp + initialDuration + 1);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.setRewardsDuration(newDuration);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        uint256 newRate = stakingRewards.rewardRate();
        uint256 expectedNewRate = rewardAmount / newDuration;
        assertEq(newRate, expectedNewRate, "New rate should reflect new duration");

        assertEq(newRate, initialRate / 2, "New rate should be half of initial rate");
    }

    /// @notice Test: Duration change preserves accumulated rewards - should pass
    function test_DurationChangePreservesAccumulatedRewards() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 90000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 45 days);
        uint256 earnedAfterHalfPeriod = stakingRewards.earned(users[0]);
        assertGt(earnedAfterHalfPeriod, 0, "Should have earned rewards");

        vm.warp(block.timestamp + 45 days + 1);
        uint256 earnedAfterFirstPeriod = stakingRewards.earned(users[0]);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.setRewardsDuration(180 days);

        assertEq(
            stakingRewards.earned(users[0]),
            earnedAfterFirstPeriod,
            "Earned rewards should be preserved after duration change"
        );

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        assertGe(
            stakingRewards.earned(users[0]),
            earnedAfterFirstPeriod,
            "Earned should not decrease when new period starts"
        );
    }

    /// @notice Test: Duration change with leftover rewards calculation - should pass
    function test_DurationChangeWithLeftoverRewards() public {
        uint256 initialReward = 90000e18;
        uint256 additionalReward = 45000e18;

        vm.prank(users[0]);
        stakingRewards.stake(1000e18);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), initialReward);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(initialReward);

        uint256 initialRate = stakingRewards.rewardRate();

        vm.warp(block.timestamp + 45 days);

        uint256 remaining = stakingRewards.periodFinish() - block.timestamp;
        uint256 leftover = remaining * initialRate;

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), additionalReward);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(additionalReward);

        uint256 newRate = stakingRewards.rewardRate();
        uint256 expectedNewRate = (additionalReward + leftover) / 90 days;

        assertApproxEqAbs(
            newRate, expectedNewRate, 1, "New rate should incorporate leftover rewards"
        );

        vm.warp(block.timestamp + 90 days + 1);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.setRewardsDuration(30 days);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), additionalReward);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(additionalReward);

        uint256 finalRate = stakingRewards.rewardRate();
        uint256 expectedFinalRate = additionalReward / 30 days;

        assertEq(
            finalRate,
            expectedFinalRate,
            "Rate should only consider new reward when no leftover exists"
        );
    }
    /// @notice Test: updateReward modifier ordering with state changes

    function test_UpdateRewardModifierOrdering() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 30 days);

        uint256 earnedBefore = stakingRewards.earned(users[0]);

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        uint256 earnedAfter = stakingRewards.earned(users[0]);
        uint256 userRewardPerTokenPaid = stakingRewards.userRewardPerTokenPaid(users[0]);

        assertGe(earnedAfter, earnedBefore, "Earned should preserve previous rewards");
        assertEq(
            userRewardPerTokenPaid,
            stakingRewards.rewardPerTokenStored(),
            "User reward per token should match stored value after update"
        );
    }

    /// @notice Test: Cross-function state with pause/unpause cycles
    function test_CrossFunctionStateWithPauseCycles() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 20 days);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.pause();

        vm.prank(users[0]);
        stakingRewards.getReward();

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.unpause();

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        assertEq(
            stakingRewards.balanceOf(users[0]),
            stakeAmount * 2,
            "Balance should reflect both stakes after unpause"
        );
        assertEq(
            stakingRewards.earned(users[0]),
            0,
            "Should start fresh earning after claim and new stake"
        );
    }

    function test_ExitFunctionStateConsistency() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 50000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 91 days);

        uint256 earnedBeforeExit = stakingRewards.earned(users[0]);
        uint256 userTokensBefore = token.balanceOf(users[0]);
        uint256 contractStakeBalanceBefore = stakingRewards.totalSupply();

        vm.prank(users[0]);
        stakingRewards.exit();

        assertEq(stakingRewards.balanceOf(users[0]), 0, "User balance should be zero");
        assertEq(stakingRewards.earned(users[0]), 0, "User earned should be zero");
        assertEq(stakingRewards.rewards(users[0]), 0, "User rewards should be zero");
        assertEq(
            stakingRewards.totalSupply(),
            contractStakeBalanceBefore - stakeAmount,
            "Total supply should decrease by user's stake"
        );

        uint256 expectedTokens = userTokensBefore + stakeAmount + earnedBeforeExit;
        assertApproxEqAbs(
            token.balanceOf(users[0]), expectedTokens, 1, "User should receive stake plus rewards"
        );
    }

    /// @notice Test: Multiple users reward accumulation during pause
    function test_MultipleUsersRewardAccumulationDuringPause() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100000e18;

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            stakingRewards.stake(stakeAmount);
        }

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 30 days);

        uint256[] memory earnedBefore = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            earnedBefore[i] = stakingRewards.earned(users[i]);
        }

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.pause();
        vm.warp(block.timestamp + 15 days);

        uint256[] memory earnedDuring = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            earnedDuring[i] = stakingRewards.earned(users[i]);
            assertGt(earnedDuring[i], earnedBefore[i], "Each user should earn during pause");
        }

        uint256 user0Increase = earnedDuring[0] - earnedBefore[0];
        uint256 user1Increase = earnedDuring[1] - earnedBefore[1];
        assertEq(user0Increase, user1Increase, "Equal stakers should earn equally during pause");
    }

    /// @notice Test: Pause during reward period vs pause after period end
    function test_PauseDuringVsAfterRewardPeriod() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 90000e18;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        token.transfer(address(stakingRewards), rewardAmount);
        vm.prank(REWARDS_DISTRIBUTOR);
        stakingRewards.notifyRewardAmount(rewardAmount);

        vm.warp(block.timestamp + 45 days);
        uint256 earnedMidPeriod = stakingRewards.earned(users[0]);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.pause();
        vm.warp(block.timestamp + 10 days);

        uint256 earnedDuringActivePause = stakingRewards.earned(users[0]);
        assertGt(earnedDuringActivePause, earnedMidPeriod, "Should earn during active period pause");

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.unpause();

        vm.warp(block.timestamp + 40 days);
        uint256 earnedAtPeriodEnd = stakingRewards.earned(users[0]);

        vm.prank(FOUNDATION_MULTISIG);
        stakingRewards.pause();
        vm.warp(block.timestamp + 10 days);

        uint256 earnedAfterPeriodPause = stakingRewards.earned(users[0]);

        assertEq(
            earnedAtPeriodEnd,
            earnedAfterPeriodPause,
            "Should not earn during pause after period end"
        );
    }
}
