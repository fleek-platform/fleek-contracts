# Creator Token Deployment and Trading Guide

This guide documents the complete flow for deploying and testing creator tokens on Base Sepolia testnet.

## Prerequisites

- Base Sepolia RPC URL configured as `$BASE_SEPOLIA_RPC`
- Funded account configured in cast keystore (e.g., `flk-deployer`)
- FLK token deployed at: `0x88DB73F86c7025608420f447ae003b7CD3286E71`

## Step 1: Deploy Infrastructure

Deploy the creator token factory and supporting contracts:

```bash
forge script script/DeployCreatorTokenFactoryTestnet.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer \
  --broadcast
```

This deploys:
- CreatorTokenFactory
- UniversalAntiFlipFeeHook (with mined address for hook flags)
- BondingCurveFactory
- CreatorCoinFactory

## Step 2: Create Creator Token

Deploy a new creator token with bonding curve:

```bash
cast send <CREATOR_TOKEN_FACTORY> "createToken(string,string)" \
  "MyToken" "MTK" \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer
```

Note the emitted CreatorTokenDeployed event containing:
- Token address
- Bonding curve address

## Step 3: Buy Tokens on Bonding Curve

Purchase tokens through the bonding curve (requires FLK approval):

```bash
# Approve bonding curve to spend FLK
cast send <FLK_TOKEN> "approve(address,uint256)" \
  <BONDING_CURVE> \
  115792089237316195423570985008687907853269984665640564039457584007913129639935 \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer

# Buy tokens (e.g., 1000 FLK worth)
cast send <BONDING_CURVE> "buy(uint256)" \
  1000000000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer
```

## Step 4: Graduate to Uniswap V4

Once sufficient liquidity is reached, graduate the token:

```bash
# Buy enough to trigger graduation (e.g., 21000 FLK)
cast send <BONDING_CURVE> "buy(uint256)" \
  21000000000000000000000 \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer
```

The graduation automatically:
- Creates a Uniswap V4 pool
- Transfers liquidity from bonding curve to pool
- Registers token with anti-flip hook

## Step 5: Approve Hook for Fee Collection

Before trading on the graduated pool, approve the hook to collect fees:

```bash
cast send <FLK_TOKEN> "approve(address,uint256)" \
  <HOOK_ADDRESS> \
  115792089237316195423570985008687907853269984665640564039457584007913129639935 \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer
```

## Step 6: Trade on Graduated Pool

### Buy Creator Tokens

Use the TestGraduatedPoolBuy script (update addresses in script first):

```bash
forge script script/TestGraduatedPoolBuy.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer \
  --broadcast
```

This script:
- Deploys a PoolSwapTest router
- Swaps FLK for creator tokens
- Shows fees collected (2% standard fee)

### Sell Creator Tokens

Use the TestGraduatedPoolSell script:

```bash
forge script script/TestGraduatedPoolSell.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer \
  --broadcast
```

This script:
- Checks anti-flip window status
- Swaps creator tokens for FLK
- Shows actual fee percentage paid
- Displays fee distribution between foundation and creator

## Fee Structure

- **Standard Fee**: 2% on all trades
- **Anti-Flip Penalty**: Additional 10% on sells within personalized window (30-120 seconds after buy)
- **Maximum Fee**: 12% (during anti-flip window)

Fee distribution varies based on creator's token holdings:
- 250k+ tokens: Foundation 75%, Creator 25%
- 150k+ tokens: Foundation 80%, Creator 20%
- 50k+ tokens: Foundation 85%, Creator 15%
- <50k tokens: Foundation 87.5%, Creator 12.5%

## Key Addresses (Example Deployment)

```
CreatorTokenFactory: 0xf734245E0cD14f9f753c97CB4a1daBa512e657F2
UniversalAntiFlipFeeHook: 0xA179D196186681bE0952E7214c386439aFCe0044
BondingCurveFactory: 0x55b975d691E41713ceE301922Ce554046F0A65Fb
Example Creator Token: 0x1aC4381a7fB097DE351f492B9468C433e455aE74
Example Bonding Curve: 0xf7ee72eE7B2920A41f5571BEEFcC601Fc1Ce0bB7
```

## Verification Commands

Check token registration in hook:
```bash
cast call <HOOK_ADDRESS> "tokenToCreator(address)(address)" \
  <CREATOR_TOKEN> \
  --rpc-url $BASE_SEPOLIA_RPC
```

Check claimable fees:
```bash
cast call <HOOK_ADDRESS> "claimableFees(address)(uint256)" \
  <ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC
```

Claim accumulated fees:
```bash
cast send <HOOK_ADDRESS> "claimFees()" \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account <FEE_RECIPIENT>
```