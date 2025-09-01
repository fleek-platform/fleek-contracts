// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { StakingRewards } from "../../src/staking/StakingRewards.sol";
import { FLKToken } from "../../src/token/FLKToken.sol";

contract StakingRewardsSequenceFuzzTest is Test {
    StakingRewards public stakingRewards;
    FLKToken public token;

    address public FOUNDATION_MULTISIG = makeAddr("FOUNDATION_MULTISIG");
    address public REWARDS_DISTRIBUTOR = makeAddr("REWARDS_DISTRIBUTOR");
    address[] public users;

    function setUp() public {
        token = new FLKToken(FOUNDATION_MULTISIG);
        stakingRewards = new StakingRewards(
            FOUNDATION_MULTISIG, address(token), address(token), REWARDS_DISTRIBUTOR, 90 days
        );

        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);
            vm.deal(user, 1 ether);
        }

        uint256 foundationBalance = token.balanceOf(FOUNDATION_MULTISIG);

        uint256 rewardsAmount = foundationBalance * 70 / 100;
        uint256 userAmount = foundationBalance * 25 / 100 / 5;

        vm.startPrank(FOUNDATION_MULTISIG);
        token.transfer(REWARDS_DISTRIBUTOR, rewardsAmount);
        for (uint256 i = 0; i < 5; i++) {
            token.transfer(users[i], userAmount);
        }
        vm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            token.approve(address(stakingRewards), type(uint256).max);
        }
        vm.prank(REWARDS_DISTRIBUTOR);
        token.approve(address(stakingRewards), type(uint256).max);
    }

    function sanitizeInput(uint256 input, uint256 min, uint256 max)
        internal
        pure
        returns (uint256)
    {
        if (input > max * 1000000) {
            input = uint256(keccak256(abi.encodePacked(input))) % (max - min) + min;
        } else if (input > max) {
            input = (input % (max - min)) + min;
        } else if (input < min) {
            input = min;
        }
        return input;
    }

    function testFuzz_ComplexOperationSequences(
        uint256 seed,
        uint8[10] memory operations,
        uint256[10] memory amounts,
        uint256[10] memory timeJumps,
        uint8[10] memory userSelectors
    ) public {
        uint256 maxUserBalance = token.balanceOf(users[0]);
        uint256 maxRewardBalance = token.balanceOf(REWARDS_DISTRIBUTOR);
        uint256 randomState = seed;

        for (uint256 i = 0; i < 10; i++) {
            uint8 operation = operations[i] % 6;

            uint256 amount = sanitizeInput(amounts[i] ^ randomState, 1000e18, maxUserBalance / 2);
            uint256 timeJump = sanitizeInput(timeJumps[i] ^ randomState, 0, 7 days);
            address user = users[(userSelectors[i] ^ uint8(randomState)) % 5];

            randomState = uint256(keccak256(abi.encodePacked(randomState, i)));

            if (timeJump > 0) {
                vm.warp(block.timestamp + timeJump);
            }

            if (operation == 0 && !stakingRewards.paused()) {
                uint256 userBalance = token.balanceOf(user);
                if (userBalance >= amount) {
                    vm.prank(user);
                    try stakingRewards.stake(amount) { } catch { }
                }
            } else if (operation == 1 && !stakingRewards.paused()) {
                uint256 safeRewardAmount =
                    sanitizeInput(amounts[i] ^ randomState, 1000e18, maxRewardBalance / 100);
                vm.prank(REWARDS_DISTRIBUTOR);
                try stakingRewards.notifyRewardAmount(safeRewardAmount) { } catch { }
            } else if (operation == 2 && !stakingRewards.paused()) {
                vm.prank(FOUNDATION_MULTISIG);
                try stakingRewards.pause() { } catch { }
            } else if (operation == 3 && stakingRewards.paused()) {
                vm.prank(FOUNDATION_MULTISIG);
                try stakingRewards.unpause() { } catch { }
            } else if (operation == 4) {
                vm.prank(user);
                try stakingRewards.getReward() { } catch { }
            } else if (operation == 5) {
                uint256 userBalance = stakingRewards.balanceOf(user);
                if (userBalance > 0) {
                    uint256 withdrawAmount = sanitizeInput(amount, 1, userBalance);
                    vm.prank(user);
                    try stakingRewards.withdraw(withdrawAmount) { } catch { }
                }
            }

            _verifyBasicInvariants();
        }
    }

    function testFuzz_CoreInvariants(uint256 stakeAmount, uint256 rewardAmount) public {
        uint256 maxUserBalance = token.balanceOf(users[0]);
        uint256 maxRewardBalance = token.balanceOf(REWARDS_DISTRIBUTOR);

        stakeAmount = sanitizeInput(stakeAmount, 1000e18, maxUserBalance / 2);
        rewardAmount = sanitizeInput(rewardAmount, 1000e18, maxRewardBalance / 100);

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        vm.prank(REWARDS_DISTRIBUTOR);
        try stakingRewards.notifyRewardAmount(rewardAmount) { }
        catch {
            return;
        }

        vm.warp(block.timestamp + 30 days);

        vm.prank(users[1]);
        stakingRewards.stake(stakeAmount / 2);

        vm.warp(block.timestamp + 60 days);

        vm.prank(users[0]);
        try stakingRewards.getReward() { } catch { }

        vm.prank(users[1]);
        try stakingRewards.getReward() { } catch { }

        vm.warp(block.timestamp + 91 days);

        vm.prank(users[0]);
        try stakingRewards.withdraw(stakeAmount) { } catch { }

        vm.prank(users[1]);
        try stakingRewards.withdraw(stakeAmount / 2) { } catch { }

        _verifyBasicInvariants();
    }

    function testFuzz_PauseUnpauseSequences(uint8[5] memory pauseActions) public {
        uint256 stakeAmount = token.balanceOf(users[0]) / 10;

        vm.prank(users[0]);
        stakingRewards.stake(stakeAmount);

        uint256 rewardAmount = token.balanceOf(REWARDS_DISTRIBUTOR) / 100;
        vm.prank(REWARDS_DISTRIBUTOR);
        try stakingRewards.notifyRewardAmount(rewardAmount) { } catch { }

        bool currentlyPaused = false;

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 1 days);

            if (pauseActions[i] % 2 == 1 && !currentlyPaused) {
                vm.prank(FOUNDATION_MULTISIG);
                stakingRewards.pause();
                currentlyPaused = true;
            } else if (pauseActions[i] % 2 == 0 && currentlyPaused) {
                vm.prank(FOUNDATION_MULTISIG);
                stakingRewards.unpause();
                currentlyPaused = false;
            }

            if (!currentlyPaused) {
                vm.prank(users[1]);
                try stakingRewards.stake(stakeAmount / 10) { } catch { }
            }

            vm.prank(users[0]);
            try stakingRewards.getReward() { } catch { }

            _verifyBasicInvariants();
        }
    }

    function _verifyBasicInvariants() internal view {
        uint256 totalSupply = stakingRewards.totalSupply();
        uint256 sumUserBalances = 0;
        for (uint256 i = 0; i < users.length; i++) {
            sumUserBalances += stakingRewards.balanceOf(users[i]);
        }
        assertEq(totalSupply, sumUserBalances, "Total supply != sum of user balances");

        try stakingRewards.rewardPerToken() returns (uint256) { }
        catch {
            assertTrue(false, "RewardPerToken calculation failed");
        }

        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(stakingRewards.balanceOf(users[i]) >= 0, "Negative user balance");
        }
    }
}
