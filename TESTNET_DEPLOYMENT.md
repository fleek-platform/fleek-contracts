# Base Sepolia Testnet Deployment Guide

Quick guide for deploying and testing the AntiFlipFeeHook system on Base Sepolia testnet.

## Testnet Configuration

**Base Sepolia Addresses:**
- Foundation: `0xF3191119E5Be5795d7DD3D60ABb949064CDcB885`
- Fan Pool Controller: `0xF3191119E5Be5795d7DD3D60ABb949064CDcB885`
- FLK Token: `0x88DB73F86c7025608420f447ae003b7CD3286E71`

**Uniswap V4 (Base Sepolia):**
- PoolManager: `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408`
- PositionManager: `0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80`
- UniversalRouter: `0x492E6456D9528771018DeB9E87ef7750EF184104`
- Quoter: `0x4A6513c898fe1B2d0E78d3b0e0A4a151589B1cBa`

## Prerequisites

```bash
# Set up environment
export PRIVATE_KEY=your_private_key_here
export BASE_SEPOLIA_RPC=https://sepolia.base.org
export BASESCAN_API_KEY=your_basescan_api_key  # For verification
```

## Step 1: Deploy Factory System

Deploy the complete factory system to Base Sepolia:

```bash
forge script script/DeployCreatorTokenFactoryTestnet.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

**What gets deployed:**
1. BondingCurve implementation (for clones)
2. BondingCurveFactory
3. CreatorCoinFactory
4. CreatorTokenFactory (owned by foundation)

**Expected output:**
```
BondingCurve implementation deployed at: 0x...
BondingCurveFactory deployed at: 0x...
CreatorCoinFactory deployed at: 0x...
CreatorTokenFactory deployed at: 0x...
```

Save these addresses!

## Step 2: Get Testnet FLK

You need FLK tokens to test. The testnet FLK is at:
`0x88DB73F86c7025608420f447ae003b7CD3286E71`

Get some from:
- Testnet faucet (if available)
- Mint function (if you have access)
- Request from the foundation address

## Step 3: Create a Test Creator Token

As the foundation owner, deploy a test creator token:

```bash
cast send <CREATOR_TOKEN_FACTORY> \
  "deployNew(address,string,string,uint64,uint64,uint64)" \
  <YOUR_CREATOR_ADDRESS> \
  "Test Creator Token" \
  "TCT" \
  $(cast block latest timestamp) \
  $((365 * 24 * 60 * 60)) \
  $((30 * 24 * 60 * 60)) \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

**Parameters:**
- Creator address: Your address (will receive fees and vested tokens)
- Name: "Test Creator Token"
- Symbol: "TCT"
- Vesting start: Current timestamp
- Vesting duration: 365 days (31,536,000 seconds)
- Cliff duration: 30 days (2,592,000 seconds)

## Step 4: Find Your Bonding Curve

Get the bonding curve address from the deployment event:

```bash
cast logs \
  --address <CREATOR_TOKEN_FACTORY> \
  --from-block latest \
  --rpc-url $BASE_SEPOLIA_RPC \
  | grep TokenDeployed
```

Look for the `TokenDeployed` event which contains:
- `newToken`: Creator token address
- `bondingCurve`: Bonding curve address
- `vestingContract`: Vesting wallet address

## Step 5: Buy Tokens on the Bonding Curve

### A. Approve FLK

```bash
cast send 0x88DB73F86c7025608420f447ae003b7CD3286E71 \
  "approve(address,uint256)" \
  <BONDING_CURVE_ADDRESS> \
  $(cast max-uint256) \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

### B. Buy Tokens

```bash
# Buy 1000 FLK worth of tokens (2% fee applied = 1020 FLK total)
cast send <BONDING_CURVE_ADDRESS> \
  "buy(uint256,uint256)" \
  1000000000000000000000 \
  0 \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

### C. Check Your Balance

```bash
cast call <CREATOR_TOKEN_ADDRESS> \
  "balanceOf(address)" \
  <YOUR_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC
```

### D. Verify Fee Collection

```bash
# Check foundation received 75% of 2% fee
cast call 0x88DB73F86c7025608420f447ae003b7CD3286E71 \
  "balanceOf(address)" \
  0xF3191119E5Be5795d7DD3D60ABb949064CDcB885 \
  --rpc-url $BASE_SEPOLIA_RPC

# Check creator received 25% of 2% fee
cast call 0x88DB73F86c7025608420f447ae003b7CD3286E71 \
  "balanceOf(address)" \
  <YOUR_CREATOR_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC
```

## Step 6: Test Quick Flip Fee

Try selling immediately to trigger the 12% fee:

### A. Check Your Buy Timestamp

```bash
cast call <BONDING_CURVE_ADDRESS> \
  "userLastBuy(address)" \
  <YOUR_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC
```

### B. Approve Creator Token

```bash
cast send <CREATOR_TOKEN_ADDRESS> \
  "approve(address,uint256)" \
  <BONDING_CURVE_ADDRESS> \
  $(cast max-uint256) \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

### C. Sell Immediately (Within Window)

```bash
# Sell some tokens - 12% fee should be applied
cast send <BONDING_CURVE_ADDRESS> \
  "sell(uint256,uint256)" \
  100000000000000000000 \
  0 \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

### D. Verify Higher Fee

The fee should be ~6x higher than the buy fee (12% vs 2%).

## Step 7: Reach Graduation

Keep buying tokens until the graduation threshold is reached:

**Graduation threshold:** 20,675 FLK worth of tokens sold

```bash
# Check how many tokens have been sold
cast call <BONDING_CURVE_ADDRESS> \
  "characterTokensSold()" \
  --rpc-url $BASE_SEPOLIA_RPC
```

When you reach ~225,000 tokens sold, graduation will happen automatically:
1. ✅ AntiFlipFeeHook deployed
2. ✅ Uniswap V4 pool created
3. ✅ All remaining liquidity added
4. ✅ LP NFT burned (liquidity locked forever)

## Step 8: Test the Hook (Post-Graduation)

After graduation, find the hook address and test swaps:

### A. Find Hook Address

```bash
# Look for the Graduated event
cast logs \
  --address <BONDING_CURVE_ADDRESS> \
  --from-block latest \
  --rpc-url $BASE_SEPOLIA_RPC \
  | grep Graduated
```

### B. Test Swaps via Uniswap Interface

Use the Uniswap interface at https://app.uniswap.org with Base Sepolia network.

Or use the UniversalRouter directly:
- UniversalRouter: `0x492E6456D9528771018DeB9E87ef7750EF184104`

**Three test scenarios:**

1. **Buy (2% fee)**
   - Swap FLK → CreatorToken
   - Verify 2% fee collected

2. **Quick Flip (12% fee)**
   - Buy CreatorToken
   - Immediately sell (within 30-120 seconds)
   - Verify 12% fee collected

3. **Normal Sell (2% fee)**
   - Buy CreatorToken
   - Wait >120 seconds
   - Sell CreatorToken
   - Verify only 2% fee collected

### C. Verify Hook Function

```bash
# Check hook configuration
cast call <HOOK_ADDRESS> "CREATOR()" --rpc-url $BASE_SEPOLIA_RPC
cast call <HOOK_ADDRESS> "CREATOR_TOKEN()" --rpc-url $BASE_SEPOLIA_RPC
cast call <HOOK_ADDRESS> "VESTING_WALLET()" --rpc-url $BASE_SEPOLIA_RPC
cast call <HOOK_ADDRESS> "graduationTimestamp()" --rpc-url $BASE_SEPOLIA_RPC

# Check user's last buy
cast call <HOOK_ADDRESS> "userLastBuy(address)" <YOUR_ADDRESS> --rpc-url $BASE_SEPOLIA_RPC
```

## Expected Fee Amounts

For a **1000 FLK swap** (at Tier 1 - 1M tokens held):

| Scenario | Fee % | Total Fee | Foundation (75%) | Creator (25%) |
|----------|-------|-----------|------------------|---------------|
| Buy | 2% | 20 FLK | 15 FLK | 5 FLK |
| Quick Flip | 12% | 120 FLK | 90 FLK | 30 FLK |
| Normal Sell | 2% | 20 FLK | 15 FLK | 5 FLK |

## Troubleshooting

### "Insufficient FLK balance"
You need testnet FLK. Make sure you have FLK at `0x88DB73F86c7025608420f447ae003b7CD3286E71`.

### "Token name exists"
Creator token names must be unique. Try a different name.

### Can't find bonding curve address
Check the transaction receipt for the `TokenDeployed` event:
```bash
cast receipt <TX_HASH> --rpc-url $BASE_SEPOLIA_RPC
```

### Hook not collecting fees
1. Make sure you've reached graduation
2. Verify hook address is correct
3. Check swaps are going through Uniswap, not the bonding curve
4. Confirm pool was initialized with the hook

## Useful Commands

```bash
# Check FLK balance
cast call 0x88DB73F86c7025608420f447ae003b7CD3286E71 \
  "balanceOf(address)" <ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC

# Check creator token balance
cast call <CREATOR_TOKEN> "balanceOf(address)" <ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC

# Check if graduated
cast call <BONDING_CURVE> "graduated()" \
  --rpc-url $BASE_SEPOLIA_RPC

# Check tokens sold
cast call <BONDING_CURVE> "characterTokensSold()" \
  --rpc-url $BASE_SEPOLIA_RPC

# Get pool info
cast call 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408 \
  "getSlot0(bytes32)" <POOL_ID> \
  --rpc-url $BASE_SEPOLIA_RPC
```

## Hook Validation Plan

**For detailed hook testing procedure, see `HOOK_TESTNET_VALIDATION.md`**

The validation plan includes:
1. ✅ Test 2% fee on bonding curve buys
2. ✅ Test 12% fee on bonding curve quick flips  
3. ✅ Verify graduation deploys hook
4. ⭐ **Test 2% fee via Uniswap V4 hook (ACTUAL HOOK EXECUTION)**
5. ⭐ **Test 12% fee via Uniswap V4 hook (ACTUAL HOOK EXECUTION)**
6. ⭐ **Test normal sell via Uniswap V4 hook**

This validates:
- `afterSwap()` execution
- `poolManager.take()` calls
- Fee collection mechanism
- Variable fee rates (2% vs 12%)
- Anti-flip window mechanism

## Next Steps

After successful testnet testing:
1. ✅ Document all deployed addresses
2. ✅ Verify all fee scenarios work correctly (see HOOK_TESTNET_VALIDATION.md)
3. ✅ Confirm anti-flip windows are working
4. ✅ Test tier calculations
5. ✅ Prepare for mainnet deployment

## Scripts Available

- **Deployment**: `script/DeployCreatorTokenFactoryTestnet.s.sol`
- **Mainnet Deployment**: `script/DeployCreatorTokenFactory.s.sol`

## Support

For detailed documentation:
- `DEPLOYMENT_GUIDE.md` - Complete deployment guide
- `TEST_SUMMARY.md` - All test documentation
- `DEPLOYMENT_READY.md` - Production readiness checklist

Run tests:
```bash
forge test --match-contract AntiFlip
```

---

**Happy testing on Base Sepolia!**
