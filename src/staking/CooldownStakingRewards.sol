// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CooldownStakingRewards - A staking contract with cooldown-based withdrawals
/// @notice Allows users to stake tokens and earn rewards over time with configurable cooldown periods
/// @dev Tokens stop earning rewards when withdrawal is requested
/// @author Fleek
contract CooldownStakingRewards is ReentrancyGuard, AccessControlDefaultAdminRules, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Role identifier for rewards distributor
    bytes32 public constant REWARDS_DISTRIBUTOR = keccak256("REWARDS_DISTRIBUTOR");

    struct WithdrawalRequest {
        uint256 amount;
        uint256 initiatedAt;
    }

    /* ========== ERRORS ========== */

    /// @notice Thrown when attempting an operation with zero amount
    error ZeroAmount();
    /// @notice Thrown when user attempts to request withdrawal for more tokens than their active balance
    error InsufficientBalance();
    /// @notice Thrown when user attempts to request withdrawal while already having a pending request
    error PendingWithdrawalExists();
    /// @notice Thrown when user attempts to cancel a withdrawal request that doesn't exist
    error NoWithdrawalRequest();
    /// @notice Thrown when trying to withdraw tokens with an active cooldown period
    error CooldownNotComplete();
    /// @notice Thrown when attempting to notify rewards with no tokens staked
    error NoActiveStakers();
    /// @notice Thrown when reward amount exceeds available balance
    error RewardTooHigh();
    /// @notice Thrown when trying to change duration while rewards are active
    error RewardsPeriodActive();
    /// @notice Thrown when trying to recover the staking token
    error CannotWithdrawStakingToken();

    /* ========== EVENTS ========== */

    /// @notice Emitted when new rewards are added to the pool
    /// @param reward Amount of reward tokens added
    event RewardAdded(uint256 reward);

    /// @notice Emitted when a user stakes tokens
    /// @param user Address of the user staking tokens
    /// @param amount Amount of tokens staked
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user requests withdrawal (tokens stop earning rewards immediately)
    /// @param user Address of the user requesting withdrawal
    /// @param amount Amount of tokens moved to pending withdrawal state (no longer earning rewards)
    event WithdrawalRequested(address indexed user, uint256 amount);

    /// @notice Emitted when a user cancels their pending withdrawal request (tokens resume earning rewards)
    /// @param user Address of the user cancelling their withdrawal request
    event WithdrawalCancelled(address indexed user);

    /// @notice Emitted when a user withdraws staked tokens
    /// @param user Address of the user withdrawing tokens
    /// @param amount Amount of tokens withdrawn
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims rewards
    /// @param user Address of the user claiming rewards
    /// @param reward Amount of reward tokens claimed
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Emitted when rewards duration is updated
    /// @param newDuration New rewards distribution duration in seconds
    event RewardsDurationUpdated(uint256 newDuration);

    /// @notice Emitted when tokens are recovered by admin
    /// @param token Address of the recovered token
    /// @param amount Amount of tokens recovered
    event Recovered(address token, uint256 amount);

    /* ========== STATE VARIABLES ========== */

    /// @notice Token distributed as rewards
    IERC20 public immutable rewardsToken;
    /// @notice Token that users stake
    IERC20 public immutable stakingToken;
    /// @notice Time users must wait before withdrawing (0 = no cooldown)
    uint256 public immutable cooldownPeriod;
    /// @notice Timestamp when current reward period ends
    uint256 public periodFinish = 0;
    /// @notice Rate of reward distribution per second
    uint256 public rewardRate = 0;
    /// @notice Duration over which rewards are distributed
    uint256 public rewardsDuration = 90 days;
    /// @notice Last time rewards were updated
    uint256 public lastUpdateTime;
    /// @notice Stored reward per token value
    uint256 public rewardPerTokenStored;

    /// @notice Reward per token paid to each user
    mapping(address user => uint256 rewardPerTokenPaid) public userRewardPerTokenPaid;
    /// @notice Accumulated rewards for each user
    mapping(address user => uint256 rewardAmount) public rewards;
    /// @notice Withdrawal requests for each user
    mapping(address => WithdrawalRequest) public withdrawalRequests;

    /// @notice Total tokens staked in the contract
    uint256 private _totalSupply;
    /// @notice Amount staked by each user
    mapping(address user => uint256 stakedAmount) private _balances;

    /// @notice Initialize the staking contract
    /// @param _initialAdmin Admin address (multisig recommended)
    /// @param _rewardsToken Token distributed as rewards
    /// @param _stakingToken Token that users stake
    /// @param _rewardsDistributor Address authorized to notify reward amounts
    /// @param _cooldownPeriod Time in seconds users must wait before withdrawing (0 for no cooldown)
    constructor(
        address _initialAdmin,
        address _rewardsToken,
        address _stakingToken,
        address _rewardsDistributor,
        uint256 _cooldownPeriod
    ) AccessControlDefaultAdminRules(3 days, _initialAdmin) {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        cooldownPeriod = _cooldownPeriod;
        _grantRole(REWARDS_DISTRIBUTOR, _rewardsDistributor);
    }

    /// @notice Grant REWARDS_DISTRIBUTOR role to an address
    /// @param rewardsDistributor Address to grant the role to
    function grantRewardsDistributor(address rewardsDistributor)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        grantRole(REWARDS_DISTRIBUTOR, rewardsDistributor);
    }

    /// @notice Revoke REWARDS_DISTRIBUTOR role from an address
    /// @param rewardsDistributor Address to revoke the role from
    function revokeRewardsDistributor(address rewardsDistributor)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revokeRole(REWARDS_DISTRIBUTOR, rewardsDistributor);
    }

    /* ========== VIEWS ========== */

    /// @notice Total amount of tokens actively earning rewards (excludes pending withdrawals)
    /// @return Total actively staked token amount currently earning rewards
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Amount of tokens actively earning rewards for an account (excludes pending withdrawals)
    /// @param account Address to check active staked balance for
    /// @return Active staked token amount currently earning rewards
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Last time rewards were applicable (current time or period end)
    /// @return Timestamp of last applicable reward time
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Current reward per token staked
    /// @return Current reward per token value
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored
            + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / _totalSupply);
    }

    /// @notice Total rewards earned by an account
    /// @param account Address to check earned rewards for
    /// @return Total earned reward amount
    function earned(address account) public view returns (uint256) {
        return _balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18
            + rewards[account];
    }

    /// @notice Total rewards to be distributed over the current duration
    /// @return Total reward amount for current duration
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /// @notice Timestamp when an account's withdrawal request becomes available for completion
    /// @param account Address to check withdrawal ready time for
    /// @return Timestamp when withdrawal can be completed (0 if no request pending)
    function withdrawalReadyTime(address account) external view returns (uint256) {
        if (withdrawalRequests[account].amount == 0) {
            return 0;
        }
        return withdrawalRequests[account].initiatedAt + cooldownPeriod;
    }

    /// @notice Check if an account can complete their pending withdrawal request
    /// @param account Address to check withdrawal readiness for
    /// @return True if withdrawal request exists and cooldown period has passed
    function isWithdrawalReady(address account) public view returns (bool) {
        WithdrawalRequest memory request = withdrawalRequests[account];
        return request.amount > 0 && block.timestamp >= request.initiatedAt + cooldownPeriod;
    }

    /// @notice Get pending withdrawal details for an account
    /// @param account Address to check
    /// @return amount Amount waiting to be withdrawn, initiatedAt When cooldown started
    function getWithdrawalRequest(address account)
        external
        view
        returns (uint256 amount, uint256 initiatedAt)
    {
        WithdrawalRequest memory request = withdrawalRequests[account];
        return (request.amount, request.initiatedAt);
    }

    /// @notice Get user's total amount of tokens in contract
    /// @param user Address to check
    /// @return Total amount of tokens in contract (active stake + pending withdrawals)
    function totalPosition(address user) external view returns (uint256) {
        return _balances[user] + withdrawalRequests[user].amount;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Stake tokens to earn rewards
    /// @param amount Amount of tokens to stake
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, ZeroAmount());

        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked({ user: msg.sender, amount: amount });
    }

    /// @notice Complete withdrawal of previously requested tokens
    /// @dev Requires cooldown period to have passed since request initiation
    /// @dev Balances were already decremented in requestWithdrawal()
    function completeWithdrawal() public nonReentrant updateReward(msg.sender) {
        require(isWithdrawalReady(msg.sender), CooldownNotComplete());
        uint256 amount = withdrawalRequests[msg.sender].amount;

        delete withdrawalRequests[msg.sender];
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn({ user: msg.sender, amount: amount });
    }

    /// @notice Request withdrawal of staked tokens (starts cooldown period, stops rewards)
    /// @param amount Amount of tokens to withdraw after cooldown
    /// @dev Tokens stop earning rewards immediately upon request
    /// @dev User can stake additional tokens during cooldown without affecting the pending withdrawal
    /// @dev Only one pending withdrawal allowed at a time - cancel existing request to modify amount
    function requestWithdrawal(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, ZeroAmount());
        require(_balances[msg.sender] >= amount, InsufficientBalance());
        require(withdrawalRequests[msg.sender].amount == 0, PendingWithdrawalExists());

        // Move tokens from active staking to pending
        _balances[msg.sender] = _balances[msg.sender] - amount;
        _totalSupply = _totalSupply - amount;

        // Track in struct only
        withdrawalRequests[msg.sender] =
            WithdrawalRequest({ amount: amount, initiatedAt: block.timestamp });
        emit WithdrawalRequested({ user: msg.sender, amount: amount });
    }

    /// @notice Cancel pending withdrawal request and return tokens to active staking
    /// @dev Allows user to cancel and continue earning rewards
    function cancelWithdrawalRequest() external nonReentrant updateReward(msg.sender) {
        require(withdrawalRequests[msg.sender].amount > 0, NoWithdrawalRequest());

        uint256 amount = withdrawalRequests[msg.sender].amount;

        // Move tokens back to active staking
        _balances[msg.sender] = _balances[msg.sender] + amount;
        _totalSupply = _totalSupply + amount;

        delete withdrawalRequests[msg.sender];
        emit WithdrawalCancelled({ user: msg.sender });
    }

    /// @notice Claim all accumulated rewards
    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid({ user: msg.sender, reward: reward });
        }
    }

    /// @notice Complete withdrawal and claim rewards in one transaction
    function exit() external {
        completeWithdrawal();
        getReward();
    }

    /// @notice Pause staking (emergency function)
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause staking
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Add new rewards to be distributed over the rewards duration
    /// @param reward Amount of reward tokens to distribute
    function notifyRewardAmount(uint256 reward)
        external
        onlyRole(REWARDS_DISTRIBUTOR)
        updateReward(address(0))
    {
        require(_totalSupply > 0, NoActiveStakers());
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance / rewardsDuration, RewardTooHigh());

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded({ reward: reward });
    }

    /// @notice Recover accidentally sent ERC20 tokens (except staking token)
    /// @param tokenAddress Address of token to recover
    /// @param tokenAmount Amount of tokens to recover
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(tokenAddress != address(stakingToken), CannotWithdrawStakingToken());
        IERC20(tokenAddress).safeTransfer(defaultAdmin(), tokenAmount);
        emit Recovered({ token: tokenAddress, amount: tokenAmount });
    }

    /// @notice Update rewards distribution duration (only when no active rewards)
    /// @param newDuration New duration in seconds
    function setRewardsDuration(uint256 newDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(block.timestamp > periodFinish, RewardsPeriodActive());
        rewardsDuration = newDuration;
        emit RewardsDurationUpdated({ newDuration: rewardsDuration });
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}
