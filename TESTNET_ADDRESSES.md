# Base Sepolia Testnet Deployment

**Deployment Date:** October 27, 2025 (Updated with chain-aware Config)  
**Deployer:** `0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9`  
**Network:** Base Sepolia (Chain ID: 84532)

## ✅ Current Deployment (Chain-Aware with Working Hook)

| Contract | Address |
|----------|---------|
| **CreatorTokenFactory** | `0xa0432d1F7945e2c87fc9FB25F26cafa2256ee022` |
| **UniversalAntiFlipFeeHook** | `0x71055B16F94533Fa4B717aDa92cA7061d37E40c8` |
| **BondingCurveFactory** | `0xa07083b64511Db327269daA5271D8374f3A6A24f` |
| **CreatorCoinFactory** | `0x610326C8f0Ec41d50D38C96f40566354E5aC69cF` |
| **BondingCurve Implementation** | `0xfEC4284ec50f743964FbaE956e68e090652fE0e1` |

### ✅ Validated Graduated Token
| Token | Address | Status |
|-------|---------|--------|
| **Test Token** | `0xaa7a5d3ff533ad5aeb3518a5b00c7d8a6b299927` | Graduated, Swap Tested ✅ |

## Configuration

| Parameter | Address |
|-----------|---------|
| **Foundation** | `0xF3191119E5Be5795d7DD3D60ABb949064CDcB885` |
| **Fan Pool Controller** | `0xF3191119E5Be5795d7DD3D60ABb949064CDcB885` |
| **FLK Token** | `0x88DB73F86c7025608420f447ae003b7CD3286E71` |

## Uniswap V4 Addresses (Base Sepolia)

| Contract | Address |
|----------|---------|
| **PoolManager** | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| **PositionManager** | `0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80` |
| **UniversalRouter** | `0x492E6456D9528771018DeB9E87ef7750EF184104` |

## Ownership Structure

- **CreatorTokenFactory**: Owned by Foundation (`0xF319...B885`)
- **BondingCurveFactory**: Owned by CreatorTokenFactory
- **CreatorCoinFactory**: Owned by CreatorTokenFactory

## Block Explorer Links

- [CreatorTokenFactory](https://sepolia.basescan.org/address/0xa0432d1F7945e2c87fc9FB25F26cafa2256ee022)
- [UniversalAntiFlipFeeHook](https://sepolia.basescan.org/address/0x71055B16F94533Fa4B717aDa92cA7061d37E40c8)
- [BondingCurveFactory](https://sepolia.basescan.org/address/0xa07083b64511Db327269daA5271D8374f3A6A24f)
- [CreatorCoinFactory](https://sepolia.basescan.org/address/0x610326C8f0Ec41d50D38C96f40566354E5aC69cF)
- [BondingCurve Implementation](https://sepolia.basescan.org/address/0xfEC4284ec50f743964FbaE956e68e090652fE0e1)
- [Test Token (Graduated)](https://sepolia.basescan.org/address/0xaa7a5d3ff533ad5aeb3518a5b00c7d8a6b299927)

## Validation Status

✅ **Basic Swap Functionality**: Tested and working
- Swap successful with proper fee collection
- Foundation received 1.5 FLK fee (75%)
- Creator received 0.5 FLK fee (25%)
- No `CurrencyNotSettled()` errors
- Hook correctly charges fees via `beforeSwap` with `BeforeSwapDelta`

🔄 **Next Steps**:
1. Test anti-flip mechanism (12% penalty on quick sells)
2. Update unit tests to work with beforeSwap pattern
3. Prepare mainnet deployment

### Quick Start Commands

**1. Create a Test Creator Token:**

```bash
cast send 0xa0432d1F7945e2c87fc9FB25F26cafa2256ee022 \
  "deployNew(address,string,string,uint64,uint64,uint64)" \
  <CREATOR_ADDRESS> \
  "Test Creator Token" \
  "TCT" \
  $(cast block latest timestamp --rpc-url $BASE_SEPOLIA_RPC) \
  $((365 * 24 * 60 * 60)) \
  $((30 * 24 * 60 * 60)) \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account flk-deployer
```

**2. Find Your Bonding Curve Address:**

```bash
cast logs \
  --address 0xa0432d1F7945e2c87fc9FB25F26cafa2256ee022 \
  --from-block latest \
  --rpc-url $BASE_SEPOLIA_RPC
```

**3. Get Testnet FLK:**

FLK Token: `0x88DB73F86c7025608420f447ae003b7CD3286E71`

**4. Continue with validation plan** in `HOOK_TESTNET_VALIDATION.md`
