// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/curve/BondingCurve.sol";
import { BondingCurveFactory } from "../src/creator-tokens/core/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../src/creator-tokens/core/CreatorCoinFactory.sol";
import { UniversalAntiFlipFeeHook } from "../src/creator-tokens/hooks/UniversalAntiFlipFeeHook.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { Config } from "../src/creator-tokens/libraries/Config.sol";
import { BaseUniswapDeployments } from "../src/creator-tokens/libraries/BaseUniswapDeployments.sol";

/**
 * @title DeployCreatorTokenFactoryTestnet
 * @notice Deploys the CreatorTokenFactory system (works on any chain via Config)
 */
contract DeployCreatorTokenFactoryTestnet is Script {
    function run() public {
        console.log("=== Deploying CreatorTokenFactory ===");
        console.log("Deployer:", msg.sender);
        console.log("");

        // 1. Pre-compute factory address BEFORE any deployments
        // Deployment order: BondingCurve(0), CreatorCoinFactory(1), Hook(2), BondingCurveFactory(3), CreatorTokenFactory(4)
        uint64 nonce = uint64(vm.getNonce(msg.sender));
        address futureFactory = vm.computeCreateAddress(msg.sender, nonce + 4);
        console.log("Pre-computed CreatorTokenFactory address:", futureFactory);
        console.log("");

        // 2. Mine salt for UniversalAntiFlipFeeHook
        console.log("Mining salt for UniversalAntiFlipFeeHook...");
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(futureFactory, BaseUniswapDeployments.POOL_MANAGER());
        bytes memory creationCode = type(UniversalAntiFlipFeeHook).creationCode;

        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, creationCode, constructorArgs);

        console.log("  Target hook address:", hookAddress);
        console.log("  Salt found:", uint256(salt));
        console.log("");

        vm.startBroadcast();

        // 3. Deploy BondingCurve implementation (nonce 0)
        BondingCurve bondingCurveImpl = new BondingCurve();
        console.log("BondingCurve implementation deployed at:", address(bondingCurveImpl));

        // 4. Deploy CreatorCoinFactory (nonce 1, owned by deployer for now)
        CreatorCoinFactory creatorCoinFactory = new CreatorCoinFactory(msg.sender);
        console.log("CreatorCoinFactory deployed at:", address(creatorCoinFactory));

        // 5. Deploy UniversalAntiFlipFeeHook (nonce 2)
        UniversalAntiFlipFeeHook deployedHook = new UniversalAntiFlipFeeHook{
            salt: salt
        }(futureFactory, BaseUniswapDeployments.POOL_MANAGER());
        require(address(deployedHook) == hookAddress, "Hook address mismatch");
        console.log("UniversalAntiFlipFeeHook deployed at:", address(deployedHook));

        // 6. Deploy BondingCurveFactory (nonce 3, owned by deployer for now)
        BondingCurveFactory bondingCurveFactory =
            new BondingCurveFactory(msg.sender, address(bondingCurveImpl), address(deployedHook));
        console.log("BondingCurveFactory deployed at:", address(bondingCurveFactory));

        // 7. Deploy CreatorTokenFactory (nonce 4, with foundation as owner and all addresses set)
        CreatorTokenFactory creatorTokenFactory = new CreatorTokenFactory(
            Config.FOUNDATION(), address(bondingCurveFactory), address(creatorCoinFactory)
        );
        console.log("CreatorTokenFactory deployed at:", address(creatorTokenFactory));
        require(address(creatorTokenFactory) == futureFactory, "Factory address mismatch");

        // 8. Transfer sub-factory ownership to main factory
        bondingCurveFactory.transferOwnership(address(creatorTokenFactory));
        console.log("BondingCurveFactory ownership transferred to CreatorTokenFactory");

        creatorCoinFactory.transferOwnership(address(creatorTokenFactory));
        console.log("CreatorCoinFactory ownership transferred to CreatorTokenFactory");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("Deployed Contracts:");
        console.log("  CreatorTokenFactory:", address(creatorTokenFactory));
        console.log("  UniversalAntiFlipFeeHook:", address(deployedHook));
        console.log("  BondingCurve Implementation:", address(bondingCurveImpl));
        console.log("  BondingCurveFactory:", address(bondingCurveFactory));
        console.log("  CreatorCoinFactory:", address(creatorCoinFactory));
        console.log("");
        console.log("CreatorTokenFactory owned by foundation:", Config.FOUNDATION());
        console.log("Ready to deploy creator tokens!");
    }
}
