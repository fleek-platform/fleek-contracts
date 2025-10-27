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

contract SwapOnGraduatedPool is Script {
    // Deployed contracts (SORTED)
    IERC20 constant token0 = IERC20(0x316Aa5eE2215Fc097fb09640e6D402e87d39752E); // Creator Token (lower address)
    IERC20 constant token1 = IERC20(0x88DB73F86c7025608420f447ae003b7CD3286E71); // FLK (higher address)
    IHooks constant hookContract = IHooks(0xCA5D9e5A45Ec409851B4be3129334b3308054044);
    
    function run() external {
        IPoolManager poolManager = IPoolManager(BaseUniswapDeployments.POOL_MANAGER());
        
        vm.startBroadcast();
        
        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(poolManager);
        console.log("PoolSwapTest deployed:", address(swapRouter));
        
        // Approve tokens
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        
        // Build pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0,
            tickSpacing: 200,
            hooks: hookContract
        });
        
        // Swap 100 FLK for Creator Tokens
        // Since token0=Creator and token1=FLK, we swap token1->token0 (zeroForOne=false)
        SwapParams memory params = SwapParams({
            zeroForOne: false, // Swap token1 (FLK) for token0 (Creator)
            amountSpecified: -100e18, // Exact input: spend 100 FLK
            sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341 // Max price limit
        });
        
        console.log("Swapping 100 FLK for Creator Tokens...");
        
        swapRouter.swap(
            poolKey,
            params,
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
        
        vm.stopBroadcast();
        
        console.log("Swap complete!");
    }
}
