# Fleek Contracts

## FLK Token
**Extended ERC20 token with modern functionality:**

- **Name**: Fleek  
- **Symbol**: FLK
- **Supply**: 100,000,000 (fixed, no minting)
- **Decimals**: 18

### Token Features

- **ERC20Permit** - Gasless approvals using signatures
- **ERC20Burnable** - Holders can burn their tokens
- **ERC1363** - Tokens that can notify contracts when transferred
- **Fixed Supply** - All 100M tokens minted at deployment

## Staking System

**Dual-pool staking rewards system with lock-based multipliers:**

### Pool Architecture

The system consists of two separate StakingRewards contracts:

1. **Base Pool** - 21-day lock period, standard rewards
2. **Boosted Pool** - 365-day lock period, enhanced rewards through higher funding

### How Staking Works

**Core Mechanics:**
- Users stake FLK tokens to earn FLK rewards over time
- Rewards are distributed continuously at a fixed rate per second
- All rewards calculations are proportional to stake size and time staked
- Uses Synthetix-style "rewardPerToken" model for gas-efficient calculations

**Reward Calculation:**
```
rewardPerToken = stored + ((timeElapsed * rewardRate * 1e18) / totalSupply)
userEarned = (userBalance * (rewardPerToken - userPaidRate)) / 1e18 + storedRewards
```

### Lock Period System

**Base Pool (21 days):**
- Tokens locked for 21 days after staking
- Standard reward rate
- Additional stakes reset the entire lock period

**Boosted Pool (365 days):**
- Tokens locked for 1 year after staking  
- Enhanced reward rate through differential funding
- Additional stakes reset the entire lock period

**Important**: Rewards can always be claimed, only token withdrawals are locked.

### Multiplier Implementation

Enhanced rewards for the boosted pool are implemented through **differential funding**, not code complexity:

- **Base Pool**: Fund with X tokens per 90-day period
- **Boosted Pool**: Fund with higher amount per 90-day period  
- **Result**: Boosted stakers automatically earn more rewards proportional to funding

### Key Functions

**For Users:**
- `stake(amount)` - Stake tokens (resets lock timer)
- `withdraw(amount)` - Withdraw staked tokens (after lock period)
- `getReward()` - Claim accumulated rewards
- `exit()` - Withdraw all tokens + claim rewards
- `earned(user)` - View pending rewards
- `unlockTime(user)` - View when tokens unlock
- `isUnlocked(user)` - Check if tokens are unlocked

**For Admins:**
- `notifyRewardAmount(amount)` - Fund rewards for next 90-day period
- `setRewardsDuration(days)` - Modify reward period length
- `pause()` / `unpause()` - Emergency controls
- `recoverERC20(token, amount)` - Recover accidentally sent tokens

### Deployment Parameters

```solidity
constructor(
    address _initialAdmin,      // Foundation Multisig
    address _rewardsToken,      // FLK token address
    address _stakingToken,      // FLK token address (same token)
    address _rewardsDistributor, // EOA/bot for funding rewards
    uint256 _lockPeriod         // 21 days for base, 365 days for boosted
)
```

## Usage Examples

**Deploy Base Pool:**
```solidity
basePool = new StakingRewards(
    multisig,
    flkToken,
    flkToken, 
    distributor,
    21 days  // 21 day lock
);
```

**Deploy Boosted Pool:**
```solidity
boostedPool = new StakingRewards(
    multisig,
    flkToken, 
    flkToken,
    distributor,
    365 days  // 1 year lock
);
```

**Fund Pools (enhanced rewards example):**
```solidity
basePool.notifyRewardAmount(100000e18);    // 100k FLK over 90 days
boostedPool.notifyRewardAmount(150000e18);  // 150k FLK over 90 days (1.5x)
```

## Build & Deploy

**Build:**
```bash
forge build
```

**Test:**
```bash
forge test
forge coverage
```

**Deploy Token:**
```bash
forge script script/DeployFLK.s.sol --rpc-url <RPC> --broadcast --keystore ~/.foundry/keystores/deployer
```

**Deploy Staking:**
```bash
forge script script/DeployFLKStaking.s.sol --rpc-url <RPC> --broadcast --keystore ~/.foundry/keystores/deployer
```


## Security Audits
[Token and Staking Contract Audit](https://0xmacro.com/library/audits/fleek-1)
