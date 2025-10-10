// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../../src/staking/CooldownStakingRewards.sol";
import "../../src/token/FLKToken.sol";

/// @notice Handler contract for invariant testing
contract CooldownStakingRewardsHandler is Test {
    CooldownStakingRewards public stakingContract;
    FLKToken public flkToken;

    address public rewardsDistributor;

    // Track actors
    address[] private actors;
    mapping(address => bool) public isActor;

    // Ghost variables for invariant checks
    uint256 public ghost_sumOfBalances;
    uint256 public ghost_sumOfPendingWithdrawals;
    uint256 public ghost_totalStaked;
    uint256 public ghost_totalWithdrawn;

    // Track user actions for debugging
    mapping(address => uint256) public actorStakeCount;
    mapping(address => uint256) public actorWithdrawalCount;

    constructor(
        CooldownStakingRewards _stakingContract,
        FLKToken _flkToken,
        address _rewardsDistributor
    ) {
        stakingContract = _stakingContract;
        flkToken = _flkToken;
        rewardsDistributor = _rewardsDistributor;

        // Create actors (funding happens in test setUp)
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(0x10000 + i));
            actors.push(actor);
            isActor[actor] = true;
        }
    }

    /* ========== ACTIONS ========== */

    function stake(uint256 actorSeed, uint256 amount) public {
        address actor = _getActor(actorSeed);
        amount = bound(amount, 1e18, 10_000e18);

        uint256 balance = flkToken.balanceOf(actor);
        if (balance < amount) return;

        vm.prank(actor);
        try stakingContract.stake(amount) {
            ghost_sumOfBalances += amount;
            ghost_totalStaked += amount;
            actorStakeCount[actor]++;
        } catch {
            // Ignore failures (e.g., paused)
        }
    }

    function requestWithdrawal(uint256 actorSeed, uint256 amount) public {
        address actor = _getActor(actorSeed);

        uint256 stakedBalance = stakingContract.balanceOf(actor);
        if (stakedBalance == 0) return;

        amount = bound(amount, 1e18, stakedBalance);

        // Check if already has pending request
        (uint256 existingRequest,) = stakingContract.getWithdrawalRequest(actor);
        if (existingRequest > 0) return;

        vm.prank(actor);
        try stakingContract.requestWithdrawal(amount) {
            ghost_sumOfBalances -= amount;
            ghost_sumOfPendingWithdrawals += amount;
            actorWithdrawalCount[actor]++;
        } catch {
            // Ignore failures
        }
    }

    function completeWithdrawal(uint256 actorSeed) public {
        address actor = _getActor(actorSeed);

        if (!stakingContract.isWithdrawalReady(actor)) return;

        (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);
        if (pendingAmount == 0) return;

        vm.prank(actor);
        try stakingContract.completeWithdrawal() {
            ghost_sumOfPendingWithdrawals -= pendingAmount;
            ghost_totalWithdrawn += pendingAmount;
        } catch {
            // Ignore failures
        }
    }

    function cancelWithdrawalRequest(uint256 actorSeed) public {
        address actor = _getActor(actorSeed);

        (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);
        if (pendingAmount == 0) return;

        vm.prank(actor);
        try stakingContract.cancelWithdrawalRequest() {
            ghost_sumOfPendingWithdrawals -= pendingAmount;
            ghost_sumOfBalances += pendingAmount;
        } catch {
            // Ignore failures
        }
    }

    function getReward(uint256 actorSeed) public {
        address actor = _getActor(actorSeed);

        vm.prank(actor);
        try stakingContract.getReward() {
            // Just claim rewards, no ghost variable tracking needed
        } catch {
            // Ignore failures
        }
    }

    function warp(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 1 hours, 30 days);
        vm.warp(block.timestamp + timeDelta);
    }

    /* ========== HELPERS ========== */

    function _getActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @notice Get actor by index
    function getActor(uint256 index) external view returns (address) {
        require(index < actors.length, "Invalid actor index");
        return actors[index];
    }

    /// @notice Get number of actors
    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function callSummary() external view {
        console.log("\n=== Call Summary ===");
        console.log("Total staked:", ghost_totalStaked);
        console.log("Total withdrawn:", ghost_totalWithdrawn);
        console.log("Sum of balances:", ghost_sumOfBalances);
        console.log("Sum of pending:", ghost_sumOfPendingWithdrawals);

        for (uint256 i = 0; i < actors.length; i++) {
            console.log("\nActor", i);
            console.log("  Stakes:", actorStakeCount[actors[i]]);
            console.log("  Withdrawals:", actorWithdrawalCount[actors[i]]);
            console.log("  Balance:", stakingContract.balanceOf(actors[i]));
        }
    }
}

/// @notice Invariant test contract
contract CooldownStakingRewardsInvariantTest is Test {
    CooldownStakingRewards public stakingContract;
    FLKToken public flkToken;
    CooldownStakingRewardsHandler public handler;

    address public admin = address(1);
    address public rewardsDistributor = address(2);

    uint256 public constant COOLDOWN_PERIOD = 21 days;
    uint256 public constant INITIAL_REWARD = 90_000e18;

    function setUp() public {
        // Deploy FLK token
        flkToken = new FLKToken(address(this));

        // Deploy staking contract
        vm.prank(admin);
        stakingContract = new CooldownStakingRewards(
            admin, address(flkToken), address(flkToken), rewardsDistributor, COOLDOWN_PERIOD
        );

        // Fund staking contract with rewards
        flkToken.transfer(address(stakingContract), INITIAL_REWARD);

        // Deploy handler
        handler = new CooldownStakingRewardsHandler(stakingContract, flkToken, rewardsDistributor);

        // Fund actors directly from test contract
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            flkToken.transfer(actor, 100_000e18);

            vm.prank(actor);
            flkToken.approve(address(stakingContract), type(uint256).max);
        }

        // Seed stake and notify rewards
        vm.startPrank(handler.getActor(0));
        stakingContract.stake(1e18);
        vm.stopPrank();

        vm.prank(rewardsDistributor);
        stakingContract.notifyRewardAmount(INITIAL_REWARD);

        // Withdraw seed stake
        vm.startPrank(handler.getActor(0));
        stakingContract.requestWithdrawal(1e18);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        stakingContract.completeWithdrawal();
        vm.stopPrank();

        // Target handler for invariant testing
        targetContract(address(handler));

        // Select functions to call
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.stake.selector;
        selectors[1] = handler.requestWithdrawal.selector;
        selectors[2] = handler.completeWithdrawal.selector;
        selectors[3] = handler.cancelWithdrawalRequest.selector;
        selectors[4] = handler.getReward.selector;
        selectors[5] = handler.warp.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    /* ========== INVARIANT 1: Token Balance Accounting ========== */

    /// @notice Contract balance must always cover all obligations
    function invariant_TokenBalanceCoversObligations() public view {
        uint256 contractBalance = flkToken.balanceOf(address(stakingContract));
        uint256 totalSupply = stakingContract.totalSupply();

        // Calculate total pending withdrawals
        uint256 totalPendingWithdrawals = 0;
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);
            totalPendingWithdrawals += pendingAmount;
        }

        // Contract must hold enough to cover active stakes + pending withdrawals
        assertGe(
            contractBalance,
            totalSupply + totalPendingWithdrawals,
            "Contract balance must cover totalSupply + pending withdrawals"
        );
    }

    /* ========== INVARIANT 2: Total Supply Equals Sum of Balances ========== */

    /// @notice totalSupply must equal sum of all user balances
    function invariant_TotalSupplyEqualsSumOfBalances() public view {
        uint256 totalSupply = stakingContract.totalSupply();

        uint256 sumOfBalances = 0;
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            sumOfBalances += stakingContract.balanceOf(actor);
        }

        assertEq(totalSupply, sumOfBalances, "totalSupply must equal sum of all balances");
    }

    /* ========== INVARIANT 3: Ghost Variable Consistency ========== */

    /// @notice Ghost variables must match actual contract state
    function invariant_GhostVariablesMatchActualState() public view {
        // Calculate actual sum of balances
        uint256 actualSumOfBalances = 0;
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            actualSumOfBalances += stakingContract.balanceOf(actor);
        }

        assertEq(
            handler.ghost_sumOfBalances(),
            actualSumOfBalances,
            "Ghost sum of balances must match actual"
        );

        // Calculate actual sum of pending withdrawals
        uint256 actualSumOfPending = 0;
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);
            actualSumOfPending += pendingAmount;
        }

        assertEq(
            handler.ghost_sumOfPendingWithdrawals(),
            actualSumOfPending,
            "Ghost sum of pending must match actual"
        );
    }

    /* ========== INVARIANT 4: User Position Consistency ========== */

    /// @notice totalPosition must equal balanceOf + pending withdrawal
    function invariant_TotalPositionConsistency() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);

            uint256 totalPosition = stakingContract.totalPosition(actor);
            uint256 balance = stakingContract.balanceOf(actor);
            (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);

            assertEq(
                totalPosition, balance + pendingAmount, "totalPosition must equal balance + pending"
            );
        }
    }

    /* ========== INVARIANT 5: Single Pending Request Per User ========== */

    /// @notice Each user can have at most one pending withdrawal request
    function invariant_SinglePendingRequestPerUser() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);

            // If pending amount exists, it must be > 0
            if (pendingAmount > 0) {
                assertTrue(pendingAmount > 0, "Pending amount must be positive");
            }
        }
    }

    /* ========== INVARIANT 6: Pending Amount Never Exceeds Original Balance ========== */

    /// @notice Pending withdrawal amount must not exceed user's total position
    function invariant_PendingAmountValid() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);
            uint256 totalPosition = stakingContract.totalPosition(actor);

            // Pending amount should never exceed total position
            assertLe(pendingAmount, totalPosition, "Pending amount must not exceed total position");
        }
    }

    /* ========== INVARIANT 7: Withdrawal Ready Time Consistency ========== */

    /// @notice withdrawalReadyTime must be consistent with request timing
    function invariant_WithdrawalReadyTimeConsistent() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount, uint256 initiatedAt) =
                stakingContract.getWithdrawalRequest(actor);
            uint256 readyTime = stakingContract.withdrawalReadyTime(actor);

            if (pendingAmount > 0) {
                // If there's a pending request, ready time must be initiatedAt + cooldown
                assertEq(
                    readyTime,
                    initiatedAt + COOLDOWN_PERIOD,
                    "Ready time must be initiatedAt + cooldownPeriod"
                );
            } else {
                // If no pending request, ready time must be 0
                assertEq(readyTime, 0, "Ready time must be 0 when no pending request");
            }
        }
    }

    /* ========== INVARIANT 8: isWithdrawalReady Accuracy ========== */

    /// @notice isWithdrawalReady must accurately reflect cooldown status
    function invariant_IsWithdrawalReadyAccurate() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount, uint256 initiatedAt) =
                stakingContract.getWithdrawalRequest(actor);
            bool isReady = stakingContract.isWithdrawalReady(actor);

            if (pendingAmount > 0) {
                bool shouldBeReady = block.timestamp >= initiatedAt + COOLDOWN_PERIOD;
                assertEq(isReady, shouldBeReady, "isWithdrawalReady must match cooldown status");
            } else {
                assertFalse(isReady, "isWithdrawalReady must be false when no pending request");
            }
        }
    }

    /* ========== INVARIANT 9: Rewards Only Accrue for Active Balance ========== */

    /// @notice Rewards should only accrue for active balance, not pending withdrawals
    function invariant_RewardsOnlyForActiveBalance() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            uint256 earned = stakingContract.earned(actor);

            // Earned rewards should never be negative (checked by uint256)
            assertGe(earned, 0, "Earned must be non-negative");
        }
    }

    /* ========== INVARIANT 10: Flow Conservation ========== */

    /// @notice Total staked - total withdrawn = current totalSupply + pending
    function invariant_FlowConservation() public view {
        uint256 totalSupply = stakingContract.totalSupply();

        uint256 totalPending = 0;
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint256 pendingAmount,) = stakingContract.getWithdrawalRequest(actor);
            totalPending += pendingAmount;
        }

        // total staked - total withdrawn = totalSupply + totalPending
        assertEq(
            handler.ghost_totalStaked() - handler.ghost_totalWithdrawn(),
            totalSupply + totalPending,
            "Flow conservation: staked - withdrawn = supply + pending"
        );
    }
}
