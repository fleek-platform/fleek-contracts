// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StakingRewards - A staking contract with optional lock periods
/// @notice Allows users to stake tokens and earn rewards over time with configurable lock periods
/// @dev Supports both immediate withdrawal (lockPeriod = 0) and time-locked staking pools
/// @author Fleek
contract StakingRewards is ReentrancyGuard, AccessControlDefaultAdminRules, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Role identifier for rewards distributor
    bytes32 public constant REWARDS_DISTRIBUTOR = keccak256("REWARDS_DISTRIBUTOR");

    /* ========== ERRORS ========== */

    /// @notice Thrown when attempting an operation with zero amount
    error ZeroAmount();
    /// @notice Thrown when trying to withdraw tokens that are still locked
    error TokensLocked();
    /// @notice Thrown when reward amount exceeds available balance
    error RewardTooHigh();
    /// @notice Thrown when trying to recover the staking token
    error CannotWithdrawStakingToken();
    /// @notice Thrown when trying to change duration while rewards are active
    error RewardsPeriodActive();

    /* ========== EVENTS ========== */

    /// @notice Emitted when new rewards are added to the pool
    /// @param reward Amount of reward tokens added
    event RewardAdded(uint256 reward);

    /// @notice Emitted when a user stakes tokens
    /// @param user Address of the user staking tokens
    /// @param amount Amount of tokens staked
    event Staked(address indexed user, uint256 amount);

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
    /// @notice Time users must wait before withdrawing (0 = no lock)
    uint256 public immutable lockPeriod;
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
    /// @notice Timestamp when each user last staked
    mapping(address user => uint256 timestamp) public stakeTimestamp;
    /// @notice Accumulated rewards for each user
    mapping(address user => uint256 rewardAmount) public rewards;

    /// @notice Total tokens staked in the contract
    uint256 private _totalSupply;
    /// @notice Amount staked by each user
    mapping(address user => uint256 stakedAmount) private _balances;

    /// @notice Initialize the staking contract
    /// @param _initialAdmin Admin address (multisig recommended)
    /// @param _rewardsToken Token distributed as rewards
    /// @param _stakingToken Token that users stake
    /// @param _rewardsDistributor Address authorized to notify reward amounts
    /// @param _lockPeriod Time in seconds users must wait before withdrawing (0 for no lock)
    constructor(
        address _initialAdmin,
        address _rewardsToken,
        address _stakingToken,
        address _rewardsDistributor,
        uint256 _lockPeriod
    ) AccessControlDefaultAdminRules(3 days, _initialAdmin) {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        lockPeriod = _lockPeriod;
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

    /// @notice Total amount of tokens staked in the contract
    /// @return Total staked token amount
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Amount of tokens staked by an account
    /// @param account Address to check staked balance for
    /// @return Staked token amount for the account
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

    /// @notice Timestamp when an account's tokens become unlocked for withdrawal
    /// @param account Address to check unlock time for
    /// @return Timestamp when tokens become unlocked
    function unlockTime(address account) external view returns (uint256) {
        return stakeTimestamp[account] + lockPeriod;
    }

    /// @notice Check if an account's staked tokens are unlocked for withdrawal
    /// @param account Address to check unlock status for
    /// @return True if tokens are unlocked, false otherwise
    function isUnlocked(address account) external view returns (bool) {
        return block.timestamp >= stakeTimestamp[account] + lockPeriod;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Stake tokens to earn rewards
    /// @param amount Amount of tokens to stake
    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, ZeroAmount());

        // Record stake timestamp (updates on new stakes)
        stakeTimestamp[msg.sender] = block.timestamp;

        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked({ user: msg.sender, amount: amount });
    }

    /// @notice Withdraw staked tokens (must be unlocked)
    /// @param amount Amount of tokens to withdraw
    /// @dev Requires lockPeriod to have passed since last stake
    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, ZeroAmount());
        require(block.timestamp >= stakeTimestamp[msg.sender] + lockPeriod, TokensLocked());

        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn({ user: msg.sender, amount: amount });
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

    /// @notice Withdraw all staked tokens and claim all rewards
    function exit() external {
        withdraw(_balances[msg.sender]);
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
