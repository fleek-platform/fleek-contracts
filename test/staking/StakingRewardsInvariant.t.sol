// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { StakingRewards } from "../../src/staking/StakingRewards.sol";
import { FLKToken } from "../../src/token/FLKToken.sol";

contract StakingRewardsInvariant is Test {
    StakingRewards public stakingRewards;
    FLKToken public token;

    address public FOUNDATION_MULTISIG;
    address public REWARDS_DISTRIBUTOR;
    address[] public users;

    uint256 public totalRewardsDistributed;
    uint256 public totalRewardsClaimed;

    modifier useActor(uint256 actorSeed) {
        address actor = users[bound(actorSeed, 0, users.length - 1)];
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    modifier useRewardsDistributor() {
        vm.startPrank(REWARDS_DISTRIBUTOR);
        _;
        vm.stopPrank();
    }

    modifier useFoundation() {
        vm.startPrank(FOUNDATION_MULTISIG);
        _;
        vm.stopPrank();
    }

    constructor(
        StakingRewards _stakingRewards,
        FLKToken _token,
        address _foundation,
        address _rewardsDistributor,
        address[] memory _users
    ) {
        stakingRewards = _stakingRewards;
        token = _token;
        FOUNDATION_MULTISIG = _foundation;
        REWARDS_DISTRIBUTOR = _rewardsDistributor;
        users = _users;
    }

    function stake(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        amount = bound(amount, 1, token.balanceOf(msg.sender));

        try stakingRewards.stake(amount) { } catch { }
    }

    function withdraw(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        uint256 balance = stakingRewards.balanceOf(msg.sender);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        try stakingRewards.withdraw(amount) { } catch { }
    }

    function getReward(uint256 actorSeed) public useActor(actorSeed) {
        uint256 earnedBefore = stakingRewards.earned(msg.sender);

        try stakingRewards.getReward() {
            totalRewardsClaimed += earnedBefore;
        } catch { }
    }

    function exit(uint256 actorSeed) public useActor(actorSeed) {
        uint256 earnedBefore = stakingRewards.earned(msg.sender);

        try stakingRewards.exit() {
            totalRewardsClaimed += earnedBefore;
        } catch { }
    }

    function notifyRewardAmount(uint256 amount) public useRewardsDistributor {
        uint256 distributorBalance = token.balanceOf(REWARDS_DISTRIBUTOR);
        if (distributorBalance == 0) return;

        amount = bound(amount, 1e18, distributorBalance / 10);

        token.transfer(address(stakingRewards), amount);

        try stakingRewards.notifyRewardAmount(amount) {
            totalRewardsDistributed += amount;
        } catch { }
    }

    function pauseContract() public useFoundation {
        if (!stakingRewards.paused()) {
            stakingRewards.pause();
        }
    }

    function unpauseContract() public useFoundation {
        if (stakingRewards.paused()) {
            stakingRewards.unpause();
        }
    }

    function setRewardsDuration(uint256 duration) public useFoundation {
        duration = bound(duration, 1 days, 365 days);

        try stakingRewards.setRewardsDuration(duration) { } catch { }
    }

    function warpTime(uint256 timeJump) public {
        timeJump = bound(timeJump, 1 minutes, 7 days);
        vm.warp(block.timestamp + timeJump);
    }

    function addRewardsToContract(uint256 amount) public useRewardsDistributor {
        uint256 balance = token.balanceOf(msg.sender);
        if (balance == 0) return;

        amount = bound(amount, 1000e18, balance / 10);
        token.transfer(address(stakingRewards), amount);
    }
}

contract StakingRewardsInvariantTest is Test {
    StakingRewards public stakingRewards;
    FLKToken public token;
    StakingRewardsInvariant public handler;

    address public FOUNDATION_MULTISIG = makeAddr("FOUNDATION_MULTISIG");
    address public REWARDS_DISTRIBUTOR = makeAddr("REWARDS_DISTRIBUTOR");

    address[] public users;
    uint256 constant NUM_USERS = 5;
    uint256 constant MAX_USER_BALANCE = 1_000_000e18;

    function setUp() public {
        token = new FLKToken(FOUNDATION_MULTISIG);
        stakingRewards = new StakingRewards(
            FOUNDATION_MULTISIG, address(token), address(token), REWARDS_DISTRIBUTOR, 90 days
        );

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

        handler = new StakingRewardsInvariant(
            stakingRewards, token, FOUNDATION_MULTISIG, REWARDS_DISTRIBUTOR, users
        );

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.stake.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.getReward.selector;
        selectors[3] = handler.exit.selector;
        selectors[4] = handler.notifyRewardAmount.selector;
        selectors[5] = handler.pauseContract.selector;
        selectors[6] = handler.unpauseContract.selector;
        selectors[7] = handler.warpTime.selector;
        selectors[8] = handler.addRewardsToContract.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    /// @notice Total supply should equal sum of all user balances
    function invariant_totalSupplyEqualsUserBalances() public view {
        uint256 totalUserBalances = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalUserBalances += stakingRewards.balanceOf(users[i]);
        }
        assertEq(stakingRewards.totalSupply(), totalUserBalances);
    }

    /// @notice Reward per token should never decrease
    function invariant_rewardPerTokenMonotonic() public view {
        uint256 currentRewardPerToken = stakingRewards.rewardPerToken();
        uint256 storedRewardPerToken = stakingRewards.rewardPerTokenStored();
        assertGe(currentRewardPerToken, storedRewardPerToken);
    }

    /// @notice Individual earned rewards should never exceed total possible
    function invariant_earnedRewardsBounds() public view {
        uint256 totalSupply = stakingRewards.totalSupply();
        if (totalSupply == 0) return;

        uint256 rewardPerToken = stakingRewards.rewardPerToken();

        for (uint256 i = 0; i < users.length; i++) {
            uint256 userBalance = stakingRewards.balanceOf(users[i]);
            uint256 userEarned = stakingRewards.earned(users[i]);
            uint256 maxPossible = (userBalance * rewardPerToken) / 1e18;

            assertLe(userEarned, maxPossible + 1);
        }
    }

    /// @notice Total rewards claimed should never exceed distributed
    function invariant_rewardsClaimedNotExceedDistributed() public view {
        uint256 totalClaimed = handler.totalRewardsClaimed();
        uint256 totalDistributed = handler.totalRewardsDistributed();

        uint256 totalPending = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalPending += stakingRewards.earned(users[i]);
        }

        assertLe(totalClaimed + totalPending, totalDistributed + users.length);
    }

    /// @notice Contract token balance should cover all staked tokens plus remaining rewards
    function invariant_contractBalanceCoversObligations() public {
        uint256 contractBalance = token.balanceOf(address(stakingRewards));
        uint256 totalStaked = stakingRewards.totalSupply();

        uint256 totalPendingRewards = 0;
        for (uint256 i = 0; i < users.length; i++) {
            totalPendingRewards += stakingRewards.earned(users[i]);
        }

        if (totalStaked > 0 || totalPendingRewards > 0) {
            uint256 totalObligations = totalStaked + totalPendingRewards;
            assertGe(
                contractBalance + 1e15,
                totalObligations,
                "Contract balance must cover obligations with rounding margin"
            );
        }
    }

    /// @notice Unlock times should respect lock period
    function invariant_unlockTimeConsistency() public view {
        for (uint256 i = 0; i < users.length; i++) {
            uint256 unlockTime = stakingRewards.unlockTime(users[i]);
            if (unlockTime > 0) {
                bool shouldBeUnlocked = block.timestamp >= unlockTime;
                bool isUnlocked = stakingRewards.isUnlocked(users[i]);
                assertEq(shouldBeUnlocked, isUnlocked);
            }
        }
    }

    /// @notice Last update time should never be in the future
    function invariant_lastUpdateTimeNotFuture() public view {
        assertLe(stakingRewards.lastUpdateTime(), block.timestamp);
    }

    /// @notice Period finish should be reasonable when rewards are active
    function invariant_periodFinishReasonable() public view {
        uint256 periodFinish = stakingRewards.periodFinish();
        uint256 rewardRate = stakingRewards.rewardRate();

        if (rewardRate > 0) {
            assertGe(periodFinish, block.timestamp);
            assertLe(periodFinish, block.timestamp + 365 days);
        }
    }

    /// @notice User reward per token paid should never exceed stored value
    function invariant_userRewardPerTokenPaidConsistency() public view {
        uint256 storedRewardPerToken = stakingRewards.rewardPerTokenStored();

        for (uint256 i = 0; i < users.length; i++) {
            uint256 userPaid = stakingRewards.userRewardPerTokenPaid(users[i]);
            assertLe(userPaid, storedRewardPerToken);
        }
    }

    /// @notice Reward rate should be consistent with remaining rewards and time
    function invariant_rewardRateConsistency() public {
        uint256 rewardRate = stakingRewards.rewardRate();
        uint256 periodFinish = stakingRewards.periodFinish();

        if (rewardRate > 0 && periodFinish > block.timestamp) {
            uint256 remainingTime = periodFinish - block.timestamp;
            uint256 remainingRewards = rewardRate * remainingTime;

            uint256 contractBalance = token.balanceOf(address(stakingRewards));
            uint256 totalStaked = stakingRewards.totalSupply();

            if (contractBalance > totalStaked) {
                assertGe(contractBalance - totalStaked + 1, remainingRewards);
            }
        }
    }
}
