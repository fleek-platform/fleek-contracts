// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../../src/staking/CooldownStakingRewards.sol";
import "../../src/token/FLKToken.sol";

contract CooldownStakingRewardsTest is Test {
    CooldownStakingRewards public stakingContract;
    FLKToken public flkToken;

    address public admin = address(1);
    address public rewardsDistributor = address(2);
    address public userA = address(3);
    address public userB = address(4);

    uint256 public constant COOLDOWN_PERIOD = 21 days;
    uint256 public constant REWARDS_DURATION = 90 days;
    uint256 public constant INITIAL_REWARD = 90_000e18; // 1000 FLK per day for 90 days

    function setUp() public {
        // Deploy FLK token
        flkToken = new FLKToken(address(this));

        // Deploy staking contract
        vm.prank(admin);
        stakingContract = new CooldownStakingRewards(
            admin, address(flkToken), address(flkToken), rewardsDistributor, COOLDOWN_PERIOD
        );

        // Fund users
        flkToken.transfer(userA, 10_000e18);
        flkToken.transfer(userB, 10_000e18);

        // Fund staking contract with rewards
        flkToken.transfer(address(stakingContract), INITIAL_REWARD);

        // Approve staking contract
        vm.prank(userA);
        flkToken.approve(address(stakingContract), type(uint256).max);

        vm.prank(userB);
        flkToken.approve(address(stakingContract), type(uint256).max);

        // CRITICAL FIX: Need at least one staker before notifying rewards
        vm.prank(userA);
        stakingContract.stake(1e18); // Seed stake

        // Notify initial rewards
        vm.prank(rewardsDistributor);
        stakingContract.notifyRewardAmount(INITIAL_REWARD);

        // Withdraw seed stake
        vm.prank(userA);
        stakingContract.requestWithdrawal(1e18);

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        vm.prank(userA);
        stakingContract.completeWithdrawal();

        // Reset timestamp to T=0 for tests
        vm.warp(1);
    }

    function test_BasicStakeRequestCompleteClaimFlow() public {
        // T=0: User stakes
        vm.startPrank(userA);
        stakingContract.stake(1000e18);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(userA), 1000e18, "Balance should be 1000");
        assertEq(stakingContract.totalSupply(), 1000e18, "Total supply should be 1000");

        // T=30 days: User earns rewards
        vm.warp(block.timestamp + 30 days);

        uint256 earnedBeforeRequest = stakingContract.earned(userA);
        assertGt(earnedBeforeRequest, 0, "Should have earned rewards");
        // Should earn approximately 30,000 FLK (30 days * 1000 FLK/day)
        assertApproxEqRel(earnedBeforeRequest, 30_000e18, 0.01e18); // 1% tolerance

        // T=30 days: User requests withdrawal
        vm.prank(userA);
        stakingContract.requestWithdrawal(1000e18);

        assertEq(stakingContract.balanceOf(userA), 0, "Balance should be 0 after request");
        assertEq(stakingContract.totalSupply(), 0, "Total supply should be 0");

        (uint256 requestAmount, uint256 initiatedAt) = stakingContract.getWithdrawalRequest(userA);
        assertEq(requestAmount, 1000e18, "Request amount should be 1000");
        assertEq(initiatedAt, block.timestamp, "Initiated at should be current time");

        assertEq(
            stakingContract.totalPosition(userA), 1000e18, "Total position should still be 1000"
        );

        // T=30-51 days: During cooldown, no new rewards
        vm.warp(block.timestamp + 10 days); // T=40 days

        uint256 earnedDuringCooldown = stakingContract.earned(userA);
        assertEq(earnedDuringCooldown, earnedBeforeRequest, "No new rewards during cooldown");

        // T=50 days: Try to complete before cooldown ends (should fail)
        vm.warp(block.timestamp + 10 days); // T=50 days (only 20 days since request)

        vm.expectRevert(CooldownStakingRewards.CooldownNotComplete.selector);
        vm.prank(userA);
        stakingContract.completeWithdrawal();

        // T=51 days: Complete withdrawal
        vm.warp(block.timestamp + 1 days); // T=51 days (21 days since request)

        assertTrue(stakingContract.isWithdrawalReady(userA), "Withdrawal should be ready");

        uint256 balanceBefore = flkToken.balanceOf(userA);
        vm.prank(userA);
        stakingContract.completeWithdrawal();

        assertEq(
            flkToken.balanceOf(userA) - balanceBefore, 1000e18, "Should receive 1000 staked tokens"
        );
        assertEq(stakingContract.totalPosition(userA), 0, "Total position should be 0");

        (uint256 requestAmountAfter,) = stakingContract.getWithdrawalRequest(userA);
        assertEq(requestAmountAfter, 0, "Request should be deleted");

        // T=51 days: Claim rewards
        vm.prank(userA);
        stakingContract.getReward();

        uint256 rewardsClaimed = flkToken.balanceOf(userA) - balanceBefore - 1000e18;
        assertApproxEqRel(rewardsClaimed, 30_000e18, 0.01e18); // Earned from T=0 to T=30

        assertEq(stakingContract.earned(userA), 0, "No rewards left");
    }

    function test_PartialWithdrawalWithAdditionalStaking() public {
        vm.prank(userA);
        stakingContract.stake(1000e18);

        assertEq(stakingContract.balanceOf(userA), 1000e18);
        assertEq(stakingContract.totalSupply(), 1000e18);

        // T=10 days: Request partial withdrawal
        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.requestWithdrawal(400e18);

        assertEq(stakingContract.balanceOf(userA), 600e18, "600 should still be earning");
        assertEq(stakingContract.totalSupply(), 600e18);

        (uint256 requestAmount, uint256 initiatedAt) = stakingContract.getWithdrawalRequest(userA);
        assertEq(requestAmount, 400e18);
        uint256 requestTime = initiatedAt;

        // T=20 days: Stake more during cooldown
        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.stake(300e18);

        assertEq(stakingContract.balanceOf(userA), 900e18, "900 should be earning");
        assertEq(stakingContract.totalSupply(), 900e18);

        // Verify cooldown timer DID NOT reset
        (, uint256 initiatedAtAfterStake) = stakingContract.getWithdrawalRequest(userA);
        assertEq(initiatedAtAfterStake, requestTime, "Cooldown timer should NOT reset");

        assertEq(stakingContract.totalPosition(userA), 1300e18, "Total position = 900 + 400");

        // T=31 days: Complete withdrawal
        vm.warp(block.timestamp + 11 days); // T=31 from request time

        assertTrue(stakingContract.isWithdrawalReady(userA));

        uint256 balanceBefore = flkToken.balanceOf(userA);
        vm.prank(userA);
        stakingContract.completeWithdrawal();

        assertEq(flkToken.balanceOf(userA) - balanceBefore, 400e18, "Withdrew 400");
        assertEq(stakingContract.balanceOf(userA), 900e18, "900 still staked");
        assertEq(stakingContract.totalPosition(userA), 900e18);
    }

    function test_CancelAndRequestDifferentAmount() public {
        // T=0: Stake
        vm.prank(userA);
        stakingContract.stake(1000e18);

        // T=10: Request withdrawal
        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.requestWithdrawal(600e18);

        assertEq(stakingContract.balanceOf(userA), 400e18);
        assertEq(stakingContract.totalSupply(), 400e18);

        (uint256 requestAmount,) = stakingContract.getWithdrawalRequest(userA);
        assertEq(requestAmount, 600e18);

        // T=15: Cancel (change of mind)
        vm.warp(block.timestamp + 5 days);

        vm.prank(userA);
        stakingContract.cancelWithdrawalRequest();

        assertEq(stakingContract.balanceOf(userA), 1000e18, "Balance restored");
        assertEq(stakingContract.totalSupply(), 1000e18, "Total supply restored");

        (uint256 requestAmountAfter,) = stakingContract.getWithdrawalRequest(userA);
        assertEq(requestAmountAfter, 0, "Request deleted");

        // T=15: Request different amount
        vm.prank(userA);
        stakingContract.requestWithdrawal(800e18);

        assertEq(stakingContract.balanceOf(userA), 200e18);
        (uint256 newRequestAmount, uint256 newInitiatedAt) =
            stakingContract.getWithdrawalRequest(userA);
        assertEq(newRequestAmount, 800e18);
        assertEq(newInitiatedAt, block.timestamp, "New timer started");

        // T=36: Complete (21 days from T=15)
        vm.warp(block.timestamp + 21 days);

        assertTrue(stakingContract.isWithdrawalReady(userA));

        vm.prank(userA);
        stakingContract.completeWithdrawal();

        assertEq(stakingContract.balanceOf(userA), 200e18, "200 still staked");
    }

    function test_CannotRequestMultipleWithdrawals() public {
        // T=0: Stake
        vm.prank(userA);
        stakingContract.stake(1000e18);

        // T=10: Request withdrawal
        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.requestWithdrawal(400e18);

        // T=15: Try to request again WITHOUT canceling
        vm.warp(block.timestamp + 5 days);

        vm.expectRevert(CooldownStakingRewards.PendingWithdrawalExists.selector);
        vm.prank(userA);
        stakingContract.requestWithdrawal(200e18);

        // Must cancel first
        vm.prank(userA);
        stakingContract.cancelWithdrawalRequest();

        // Then can request new amount
        vm.prank(userA);
        stakingContract.requestWithdrawal(200e18);

        (uint256 requestAmount,) = stakingContract.getWithdrawalRequest(userA);
        assertEq(requestAmount, 200e18);
    }

    function test_CannotRequestMoreThanBalance() public {
        // T=0: Stake
        vm.prank(userA);
        stakingContract.stake(1000e18);

        // T=10: Request more than balance
        vm.warp(block.timestamp + 10 days);

        vm.expectRevert(CooldownStakingRewards.InsufficientBalance.selector);
        vm.prank(userA);
        stakingContract.requestWithdrawal(1500e18);
    }

    function test_CannotCompleteBeforeCooldownEnds() public {
        // T=0: Stake
        vm.prank(userA);
        stakingContract.stake(1000e18);

        // T=10: Request
        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.requestWithdrawal(1000e18);

        // T=20: Try to complete (only 10 days passed, need 21)
        vm.warp(block.timestamp + 10 days);

        assertFalse(stakingContract.isWithdrawalReady(userA));

        vm.expectRevert(CooldownStakingRewards.CooldownNotComplete.selector);
        vm.prank(userA);
        stakingContract.completeWithdrawal();

        // T=31: Now can complete
        vm.warp(block.timestamp + 11 days);

        assertTrue(stakingContract.isWithdrawalReady(userA));

        vm.prank(userA);
        stakingContract.completeWithdrawal();
    }

    function test_RewardsAccountingWithMultipleUsers() public {
        // Setup: 2 users staking
        // User A stakes 1000
        // User B stakes 1000
        // _totalSupply = 2000
        // Reward rate = 1000 FLK/day

        vm.prank(userA);
        stakingContract.stake(1000e18);

        vm.prank(userB);
        stakingContract.stake(1000e18);

        assertEq(stakingContract.totalSupply(), 2000e18);

        // T=0-10: Both earning equally
        vm.warp(block.timestamp + 10 days);

        uint256 earnedA = stakingContract.earned(userA);
        uint256 earnedB = stakingContract.earned(userB);

        // Each earns: 10 days * 1000 FLK/day * (1000/2000) = 5000 FLK
        assertApproxEqRel(earnedA, 5000e18, 0.01e18);
        assertApproxEqRel(earnedB, 5000e18, 0.01e18);
        assertApproxEqRel(earnedA, earnedB, 0.01e18); // Should be equal

        // T=10: User A requests withdrawal of 600
        vm.prank(userA);
        stakingContract.requestWithdrawal(600e18);

        assertEq(stakingContract.balanceOf(userA), 400e18);
        assertEq(stakingContract.balanceOf(userB), 1000e18);
        assertEq(stakingContract.totalSupply(), 1400e18);

        // T=10-20: Different earning rates
        vm.warp(block.timestamp + 10 days);

        uint256 earnedA_T20 = stakingContract.earned(userA);
        uint256 earnedB_T20 = stakingContract.earned(userB);

        // User A earns from T=10-20: 10 days * 1000 * (400/1400) ≈ 2857 FLK
        // Total for A: 5000 + 2857 ≈ 7857 FLK
        assertApproxEqRel(earnedA_T20, 7857e18, 0.01e18);

        // User B earns from T=10-20: 10 days * 1000 * (1000/1400) ≈ 7143 FLK
        // Total for B: 5000 + 7143 ≈ 12143 FLK
        assertApproxEqRel(earnedB_T20, 12_143e18, 0.01e18);

        // Verify total distributed
        uint256 totalEarned = earnedA_T20 + earnedB_T20;
        assertApproxEqRel(totalEarned, 20_000e18, 0.01e18); // 20 days * 1000 FLK/day
    }

    function test_ExitFunctionCombo() public {
        // T=0: Stake
        vm.prank(userA);
        stakingContract.stake(1000e18);

        // T=10: Request
        vm.warp(block.timestamp + 10 days);

        uint256 earnedBeforeRequest = stakingContract.earned(userA);
        assertGt(earnedBeforeRequest, 0);

        vm.prank(userA);
        stakingContract.requestWithdrawal(1000e18);

        // T=31: Exit (complete + claim in one call)
        vm.warp(block.timestamp + 21 days);

        uint256 balanceBefore = flkToken.balanceOf(userA);

        vm.prank(userA);
        stakingContract.exit();

        uint256 balanceAfter = flkToken.balanceOf(userA);
        uint256 received = balanceAfter - balanceBefore;

        // Should receive staked tokens + rewards
        assertGt(received, 1000e18, "Should receive stake + rewards");
        assertApproxEqRel(received, 1000e18 + earnedBeforeRequest, 0.01e18);

        assertEq(stakingContract.balanceOf(userA), 0);
        assertEq(stakingContract.totalPosition(userA), 0);
        assertEq(stakingContract.earned(userA), 0);
    }

    function test_CannotNotifyRewardsWithNoActiveStakers() public {
        // T=0: User stakes
        vm.prank(userA);
        stakingContract.stake(1000e18);

        assertEq(stakingContract.totalSupply(), 1000e18);

        // T=10: User requests withdrawal
        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.requestWithdrawal(1000e18);

        assertEq(stakingContract.totalSupply(), 0);

        // T=15: Admin tries to notify rewards
        vm.warp(block.timestamp + 5 days);

        vm.expectRevert(CooldownStakingRewards.NoActiveStakers.selector);
        vm.prank(rewardsDistributor);
        stakingContract.notifyRewardAmount(1000e18);
    }

    function test_PauseUnpauseBehavior() public {
        // Setup: User has staked tokens and pending withdrawal
        vm.prank(userA);
        stakingContract.stake(1000e18);

        vm.warp(block.timestamp + 10 days);

        vm.prank(userA);
        stakingContract.requestWithdrawal(500e18);

        // Admin pauses
        vm.prank(admin);
        stakingContract.pause();

        // Try to stake (should fail with EnforcedPause)
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(userA);
        stakingContract.stake(100e18);

        // Can still cancel
        vm.prank(userA);
        stakingContract.cancelWithdrawalRequest();

        // Can still request withdrawal
        vm.prank(userA);
        stakingContract.requestWithdrawal(700e18);

        assertEq(stakingContract.balanceOf(userA), 300e18);

        // Can still complete withdrawal
        vm.warp(block.timestamp + 21 days);

        vm.prank(userA);
        stakingContract.completeWithdrawal();

        assertEq(stakingContract.balanceOf(userA), 300e18);

        // Can still claim rewards
        vm.prank(userA);
        stakingContract.getReward();

        // Admin unpauses
        vm.prank(admin);
        stakingContract.unpause();

        // Now can stake again
        vm.prank(userA);
        stakingContract.stake(100e18);

        assertEq(stakingContract.balanceOf(userA), 400e18);
    }

    /* ========== HELPER TESTS ========== */

    function test_WithdrawalReadyTime() public {
        vm.prank(userA);
        stakingContract.stake(1000e18);

        // No pending request
        assertEq(stakingContract.withdrawalReadyTime(userA), 0);

        // Request withdrawal
        uint256 requestTime = block.timestamp + 10 days;
        vm.warp(requestTime);

        vm.prank(userA);
        stakingContract.requestWithdrawal(500e18);

        assertEq(
            stakingContract.withdrawalReadyTime(userA),
            requestTime + COOLDOWN_PERIOD,
            "Ready time should be request time + cooldown"
        );
    }

    function test_TotalPosition() public {
        vm.prank(userA);
        stakingContract.stake(1000e18);

        assertEq(stakingContract.totalPosition(userA), 1000e18);

        vm.prank(userA);
        stakingContract.requestWithdrawal(400e18);

        assertEq(stakingContract.balanceOf(userA), 600e18);
        assertEq(stakingContract.totalPosition(userA), 1000e18);

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        vm.prank(userA);
        stakingContract.completeWithdrawal();

        assertEq(stakingContract.totalPosition(userA), 600e18);
    }
}
