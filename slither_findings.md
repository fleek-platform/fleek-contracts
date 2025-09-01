## Staking Findings

```sh
slither --filter-paths "lib/" src/staking/StakingRewards.sol
```
```sh
'forge config --json' running
'/Users/mulf/.solc-select/artifacts/solc-0.8.30/solc-0.8.30 --version' running
'/Users/mulf/.solc-select/artifacts/solc-0.8.30/solc-0.8.30 @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ erc4626-tests/=lib/openzeppelin-contracts/lib/erc4626-tests/ forge-std/=lib/forge-std/src/ halmos-cheatcodes/=lib/openzeppelin-contracts/lib/halmos-cheatcodes/src/ openzeppelin-contracts/=lib/openzeppelin-contracts/ src/staking/StakingRewards.sol --combined-json abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc,hashes --optimize --optimize-runs 10000 --evm-version cancun --allow-paths .,/Users/mulf/work/flk-token/src/staking' running
INFO:Detectors:
StakingRewards.lastTimeRewardApplicable() (src/staking/StakingRewards.sol#130-132) uses timestamp for comparisons
        Dangerous comparisons:
        - block.timestamp < periodFinish (src/staking/StakingRewards.sol#131)
StakingRewards.isUnlocked(address) (src/staking/StakingRewards.sol#160-162) uses timestamp for comparisons
        Dangerous comparisons:
        - block.timestamp >= stakeTimestamp[account] + lockPeriod (src/staking/StakingRewards.sol#161)
StakingRewards.withdraw(uint256) (src/staking/StakingRewards.sol#182-190) uses timestamp for comparisons
        Dangerous comparisons:
        - require(bool,error)(block.timestamp >= stakeTimestamp[msg.sender] + lockPeriod,revert TokensLocked()()) (src/staking/StakingRewards.sol#184)
StakingRewards.getReward() (src/staking/StakingRewards.sol#193-200) uses timestamp for comparisons
        Dangerous comparisons:
        - reward > 0 (src/staking/StakingRewards.sol#195)
StakingRewards.notifyRewardAmount(uint256) (src/staking/StakingRewards.sol#222-245) uses timestamp for comparisons
        Dangerous comparisons:
        - block.timestamp >= periodFinish (src/staking/StakingRewards.sol#227)
        - require(bool,error)(rewardRate <= balance / rewardsDuration,revert RewardTooHigh()()) (src/staking/StakingRewards.sol#240)
StakingRewards.setRewardsDuration(uint256) (src/staking/StakingRewards.sol#261-265) uses timestamp for comparisons
        Dangerous comparisons:
        - require(bool,error)(block.timestamp > periodFinish,revert RewardsPeriodActive()()) (src/staking/StakingRewards.sol#262)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#block-timestamp
INFO:Slither:src/staking/StakingRewards.sol analyzed (17 contracts with 100 detectors), 6 result(s) found
```

The Slither warnings are false positives. These timestamp comparisons are intentional:

Block timestamp manipulation resistance: The 15-second miner manipulation window is negligible for:

90-day reward periods
Reward rate calculations

## Token Findings

```sh
 slither --filter-paths "lib/" src/token/FLKToken.sol
```

```sh
'forge config --json' running
'/Users/mulf/.solc-select/artifacts/solc-0.8.30/solc-0.8.30 --version' running
'/Users/mulf/.solc-select/artifacts/solc-0.8.30/solc-0.8.30 @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ erc4626-tests/=lib/openzeppelin-contracts/lib/erc4626-tests/ forge-std/=lib/forge-std/src/ halmos-cheatcodes/=lib/openzeppelin-contracts/lib/halmos-cheatcodes/src/ openzeppelin-contracts/=lib/openzeppelin-contracts/ src/token/FLKToken.sol --combined-json abi,ast,bin,bin-runtime,srcmap,srcmap-runtime,userdoc,devdoc,hashes --optimize --optimize-runs 10000 --evm-version cancun --allow-paths .,/Users/mulf/work/flk-token/src/token' running
INFO:Slither:src/token/FLKToken.sol analyzed (30 contracts with 100 detectors), 0 result(s) found
```
