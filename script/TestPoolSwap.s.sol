// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestPoolSwap is Script {
    // Deployed contracts
    address constant CREATOR_TOKEN = 0x316Aa5eE2215Fc097fb09640e6D402e87d39752E;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant HOOK = 0xCA5D9e5A45Ec409851B4be3129334b3308054044;
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    
    function run() public {
        console.log("=== TESTING UNISWAP V4 POOL ===");
        console.log("");
        
        // Sort tokens to get correct order
        (address token0, address token1) = FLK_TOKEN < CREATOR_TOKEN 
            ? (FLK_TOKEN, CREATOR_TOKEN)
            : (CREATOR_TOKEN, FLK_TOKEN);
            
        console.log("Token 0:", token0);
        console.log("Token 1:", token1);
        console.log("Hook:", HOOK);
        console.log("");
        
        // Build pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(HOOK)
        });
        
        // Check balances
        address user = msg.sender;
        uint256 flkBalance = IERC20(FLK_TOKEN).balanceOf(user);
        uint256 creatorBalance = IERC20(CREATOR_TOKEN).balanceOf(user);
        
        console.log("Your balances:");
        console.log("  FLK:", flkBalance / 1e18);
        console.log("  Creator Token:", creatorBalance / 1e18);
        console.log("");
        
        console.log("To test the pool, you need to:");
        console.log("");
        console.log("1. Deploy a swap router contract (PoolSwapTest)");
        console.log("2. Approve tokens for the swap router");
        console.log("3. Execute a swap");
        console.log("");
        console.log("Since we're on testnet, let's use cast commands:");
        console.log("");
        console.log("For now, check the pool state:");
        console.log("");
        console.log("# Get pool slot0 (price, tick, etc)");
        console.log("cast call", POOL_MANAGER, "\\");
        console.log('  "getSlot0(bytes32)" \\');
        console.log("  $(cast keccak $(cast abi-encode 'f(address,address,uint24,int24,address)' \\");
        console.log("    ", token0, "\\");
        console.log("    ", token1, "\\");
        console.log("    0 200", HOOK, ")) \\");
        console.log("  --rpc-url $BASE_SEPOLIA_RPC");
        console.log("");
        console.log("# Get pool liquidity");
        console.log("cast call", POOL_MANAGER, "\\");
        console.log('  "getLiquidity(bytes32)" \\');
        console.log("  $(cast keccak $(cast abi-encode 'f(address,address,uint24,int24,address)' \\");
        console.log("    ", token0, "\\");
        console.log("    ", token1, "\\");
        console.log("    0 200", HOOK, ")) \\");
        console.log("  --rpc-url $BASE_SEPOLIA_RPC");
    }
}
