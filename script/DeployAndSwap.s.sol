// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { BaseUniswapDeployments } from "../src/creator-tokens/libraries/BaseUniswapDeployments.sol";
import { AntiFlipFeeHook } from "../src/creator-tokens/hooks/AntiFlipFeeHook.sol";

/**
 * @title DeployAndSwap
 * @notice Deploy PoolSwapTest and execute a swap to test the graduated pool
 * @dev This will:
 *      1. Deploy PoolSwapTest contract (if needed)
 *      2. Approve tokens
 *      3. Execute a swap
 *      4. Show results including fees
 */
contract DeployAndSwap is Script {
    // Deployed contracts from graduation
    address constant CREATOR_TOKEN = 0x316Aa5eE2215Fc097fb09640e6D402e87d39752E;
    address constant FLK_TOKEN = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    address constant HOOK = 0xCA5D9e5A45Ec409851B4be3129334b3308054044;
    
    // Pool parameters
    uint24 constant FEE = 0;
    int24 constant TICK_SPACING = 200;
    
    function run() external {
        console.log("=== SWAP TEST ON GRADUATED POOL ===");
        console.log("");
        
        address swapper = msg.sender;
        IPoolManager poolManager = IPoolManager(BaseUniswapDeployments.POOL_MANAGER());
        
        vm.startBroadcast();
        
        // Deploy PoolSwapTest
        PoolSwapTest swapRouter = new PoolSwapTest(poolManager);
        console.log("PoolSwapTest deployed at:", address(swapRouter));
        console.log("");
        
        // Sort tokens
        (address token0, address token1) = FLK_TOKEN < CREATOR_TOKEN 
            ? (FLK_TOKEN, CREATOR_TOKEN)
            : (CREATOR_TOKEN, FLK_TOKEN);
        
        bool flkIsToken0 = token0 == FLK_TOKEN;
        
        console.log("Pool:");
        console.log("  Token0:", token0, flkIsToken0 ? "(FLK)" : "(Creator)");
        console.log("  Token1:", token1, flkIsToken0 ? "(Creator)" : "(FLK)");
        console.log("  Hook:", HOOK);
        console.log("");
        
        // Check balances before
        uint256 flkBefore = IERC20(FLK_TOKEN).balanceOf(swapper);
        uint256 creatorBefore = IERC20(CREATOR_TOKEN).balanceOf(swapper);
        
        console.log("Balances Before:");
        console.log("  FLK:", flkBefore / 1e18);
        console.log("  Creator:", creatorBefore / 1e18);
        console.log("");
        
        // Build pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });
        
        // Approve tokens
        IERC20(FLK_TOKEN).approve(address(swapRouter), type(uint256).max);
        IERC20(CREATOR_TOKEN).approve(address(swapRouter), type(uint256).max);
        console.log("Tokens approved");
        console.log("");
        
        // Execute swap: Buy Creator Tokens with 100 FLK
        // zeroForOne = true means swapping token0 -> token1
        bool zeroForOne = flkIsToken0; // Swap FLK (token0) for Creator (token1)
        
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -100e18, // Negative = exact input (spend exactly 100 tokens)
            sqrtPriceLimitX96: zeroForOne 
                ? 4295128740  // Min price (max slippage down)
                : 1461446703485210103287273052203988822378723970341 // Max price (max slippage up)
        });
        
        console.log("Executing swap: 100 FLK -> Creator Tokens");
        console.log("");
        
        swapRouter.swap(poolKey, params, PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        }), "");
        
        // Check balances after
        uint256 flkAfter = IERC20(FLK_TOKEN).balanceOf(swapper);
        uint256 creatorAfter = IERC20(CREATOR_TOKEN).balanceOf(swapper);
        
        console.log("Balances After:");
        console.log("  FLK:", flkAfter / 1e18);
        console.log("  Creator:", creatorAfter / 1e18);
        console.log("");
        
        console.log("Changes:");
        console.log("  FLK spent:", (flkBefore - flkAfter) / 1e18);
        console.log("  Creator received:", (creatorAfter - creatorBefore) / 1e18);
        console.log("");
        
        // Check hook (foundation and creator should have received fees)
        address foundation = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
        
        // Get creator address from hook
        AntiFlipFeeHook hook = AntiFlipFeeHook(HOOK);
        address creator = hook.CREATOR();
        
        console.log("Fee Distribution:");
        console.log("  Foundation FLK balance:", IERC20(FLK_TOKEN).balanceOf(foundation) / 1e18);
        console.log("  Creator FLK balance:", IERC20(FLK_TOKEN).balanceOf(creator) / 1e18);
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("Swap complete! Check that:");
        console.log("  1. You received Creator tokens");
        console.log("  2. FLK was taken (including 2% fee)");
        console.log("  3. Foundation and Creator received fee splits");
    }
}
