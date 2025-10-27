// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { BaseUniswapDeployments } from "../src/creator-tokens/libraries/BaseUniswapDeployments.sol";

/// @notice Test script to swap on the graduated bonding curve pool
/// @dev Uses a simple swap router interface - you may need to adjust based on your router
contract TestGraduatedPoolSwap is Script {
    // Deployed contracts from graduation
    address constant CREATOR_TOKEN = 0x316Aa5eE2215Fc097fb09640e6D402e87d39752E;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant HOOK = 0xCA5D9e5A45Ec409851B4be3129334b3308054044;
    
    // Pool parameters
    uint24 constant FEE = 0;
    int24 constant TICK_SPACING = 200;
    
    function run() external {
        console.log("=== TESTING GRADUATED POOL SWAP ===");
        console.log("");
        
        address swapper = msg.sender;
        
        // Get router address
        address swapRouter = BaseUniswapDeployments.UNIVERSAL_ROUTER();
        
        // Sort tokens
        (address token0, address token1) = FLK_TOKEN < CREATOR_TOKEN 
            ? (FLK_TOKEN, CREATOR_TOKEN)
            : (CREATOR_TOKEN, FLK_TOKEN);
        
        console.log("Pool Configuration:");
        console.log("  Token0:", token0, token0 == FLK_TOKEN ? "(FLK)" : "(Creator)");
        console.log("  Token1:", token1, token1 == FLK_TOKEN ? "(FLK)" : "(Creator)");
        console.log("  Hook:", HOOK);
        console.log("  Fee:", FEE);
        console.log("  Tick Spacing:", uint256(int256(TICK_SPACING)));
        console.log("");
        
        console.log("Router:");
        console.log("  Universal Router:", swapRouter);
        console.log("");
        
        // Check balances
        uint256 flkBalance = IERC20(FLK_TOKEN).balanceOf(swapper);
        uint256 creatorBalance = IERC20(CREATOR_TOKEN).balanceOf(swapper);
        
        console.log("Your Balances:");
        console.log("  FLK:", flkBalance / 1e18);
        console.log("  Creator Token:", creatorBalance / 1e18);
        console.log("");
        
        // Build pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });
        
        console.log("=== SWAP TEST OPTIONS ===");
        console.log("");
        console.log("Test 1: BUY Creator Tokens (FLK -> Creator)");
        console.log("  - Swap 100 FLK for Creator Tokens");
        console.log("  - Hook should take 2% fee from FLK");
        console.log("  - Foundation gets 75%, Creator gets 25% of fee");
        console.log("");
        console.log("Test 2: SELL Creator Tokens (Creator -> FLK)");
        console.log("  - Swap 1000 Creator Tokens for FLK");
        console.log("  - Hook should take 2% fee from FLK received");
        console.log("  - Check if within anti-flip window (30-120s)");
        console.log("");
        
        console.log("NOTE: Universal Router on testnet may have different interface.");
        console.log("You may need to use a swap router contract or the Uniswap V4 frontend.");
        console.log("");
        console.log("For manual testing, you can:");
        console.log("1. Deploy a PoolSwapTest contract");
        console.log("2. Approve tokens for it");
        console.log("3. Call swap() with the pool key");
        console.log("");
        console.log("Or check if there's a Uniswap V4 testnet UI for Base Sepolia.");
    }
    
    /// @notice Helper to get pool ID for querying
    function getPoolId() public pure returns (bytes32) {
        (address token0, address token1) = FLK_TOKEN < CREATOR_TOKEN 
            ? (FLK_TOKEN, CREATOR_TOKEN)
            : (CREATOR_TOKEN, FLK_TOKEN);
            
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });
        
        return keccak256(abi.encode(poolKey));
    }
}
