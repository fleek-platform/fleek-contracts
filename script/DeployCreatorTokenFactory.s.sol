// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/curve/BondingCurve.sol";
import { BondingCurveFactory } from "../src/creator-tokens/core/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../src/creator-tokens/core/CreatorCoinFactory.sol";
import { UniversalAntiFlipFeeHook } from "../src/creator-tokens/hooks/UniversalAntiFlipFeeHook.sol";
import { Config } from "../src/creator-tokens/libraries/Config.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { BaseUniswapDeployments } from "../src/creator-tokens/libraries/BaseUniswapDeployments.sol";

contract DeployCreatorTokenFactory is Script {
    function run() public {
        // STEP 0: Pre-compute factory address
        address deployer = msg.sender;
        uint64 deployerNonce = uint64(vm.getNonce(deployer));
        
        // Compute future CreatorTokenFactory address (nonce 1)
        address futureCreatorTokenFactory = vm.computeCreateAddress(deployer, deployerNonce + 1);
        
        console.log("Pre-computed addresses:");
        console.log("  Deployer:", deployer);
        console.log("  Deployer nonce:", deployerNonce);
        console.log("  Future CreatorTokenFactory:", futureCreatorTokenFactory);
        console.log("");
        
        // STEP 1: Mine salt for UniversalAntiFlipFeeHook
        console.log("Mining salt for UniversalAntiFlipFeeHook...");
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);
        
        bytes memory constructorArgs = abi.encode(futureCreatorTokenFactory, BaseUniswapDeployments.POOL_MANAGER());
        bytes memory creationCode = type(UniversalAntiFlipFeeHook).creationCode;
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            flags,
            creationCode,
            constructorArgs
        );
        
        console.log("  Target hook address:", hookAddress);
        console.log("  Salt found:", uint256(salt));
        console.log("");

        vm.startBroadcast();

        // Deploy CreatorCoinFactory (nonce 0)
        CreatorCoinFactory creatorCoinFactory = new CreatorCoinFactory(msg.sender);
        console.log("CreatorCoinFactory deployed at:", address(creatorCoinFactory));

        // Deploy CreatorTokenFactory (nonce 1) - should match pre-computed address
        CreatorTokenFactory creatorTokenFactory = new CreatorTokenFactory(
            Config.FOUNDATION(),
            address(0), // placeholder
            address(creatorCoinFactory)
        );
        console.log("CreatorTokenFactory deployed at:", address(creatorTokenFactory));
        require(address(creatorTokenFactory) == futureCreatorTokenFactory, "Factory address mismatch");

        // 3. Deploy UniversalAntiFlipFeeHook with correct factory address and mined salt
        UniversalAntiFlipFeeHook deployedHook = new UniversalAntiFlipFeeHook{salt: salt}(
            address(creatorTokenFactory),
            BaseUniswapDeployments.POOL_MANAGER()
        );
        require(address(deployedHook) == hookAddress, "Hook address mismatch");
        console.log("UniversalAntiFlipFeeHook deployed at:", address(deployedHook));

        // 4. Deploy BondingCurve implementation
        BondingCurve bondingCurveImpl = new BondingCurve();
        console.log("BondingCurve implementation deployed at:", address(bondingCurveImpl));

        // 5. Deploy BondingCurveFactory with hook address
        BondingCurveFactory bondingCurveFactory = new BondingCurveFactory(
            msg.sender,
            address(bondingCurveImpl),
            address(deployedHook)
        );
        console.log("BondingCurveFactory deployed at:", address(bondingCurveFactory));

        // 6. Redeploy CreatorTokenFactory with correct BondingCurveFactory
        creatorCoinFactory.transferOwnership(address(this));
        
        creatorTokenFactory = new CreatorTokenFactory(
            Config.FOUNDATION(),
            address(bondingCurveFactory),
            address(creatorCoinFactory)
        );
        console.log("CreatorTokenFactory redeployed at:", address(creatorTokenFactory));

        // 7. Transfer ownership of sub-factories to main factory
        bondingCurveFactory.transferOwnership(address(creatorTokenFactory));
        console.log("BondingCurveFactory ownership transferred to CreatorTokenFactory");

        creatorCoinFactory.transferOwnership(address(creatorTokenFactory));
        console.log("CreatorCoinFactory ownership transferred to CreatorTokenFactory");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("UniversalAntiFlipFeeHook:", address(deployedHook));
        console.log("BondingCurve Implementation:", address(bondingCurveImpl));
        console.log("CreatorTokenFactory:", address(creatorTokenFactory));
        console.log("BondingCurveFactory:", address(bondingCurveFactory));
        console.log("CreatorCoinFactory:", address(creatorCoinFactory));
    }
}
