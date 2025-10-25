// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/BondingCurve.sol";
import { BondingCurveFactory } from "../src/creator-tokens/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../src/creator-tokens/CreatorCoinFactory.sol";
import { FactoryConfig } from "../src/creator-tokens/lib/FactoryConfig.sol";

contract DeployCreatorTokenFactory is Script {
    function run() public {
        vm.startBroadcast();

        // 1. Deploy BondingCurve implementation (used by clones)
        BondingCurve bondingCurveImpl = new BondingCurve();
        console.log("BondingCurve implementation deployed at:", address(bondingCurveImpl));

        // 2. Deploy sub-factories (deployer is initial owner)
        BondingCurveFactory bondingCurveFactory = new BondingCurveFactory(
            msg.sender,
            address(bondingCurveImpl)
        );
        console.log("BondingCurveFactory deployed at:", address(bondingCurveFactory));

        CreatorCoinFactory creatorCoinFactory = new CreatorCoinFactory(msg.sender);
        console.log("CreatorCoinFactory deployed at:", address(creatorCoinFactory));

        // 3. Deploy main factory
        CreatorTokenFactory creatorTokenFactory = new CreatorTokenFactory(
            FactoryConfig.FOUNDATION, address(bondingCurveFactory), address(creatorCoinFactory)
        );
        console.log("CreatorTokenFactory deployed at:", address(creatorTokenFactory));

        // 4. Transfer ownership of sub-factories to main factory
        bondingCurveFactory.transferOwnership(address(creatorTokenFactory));
        console.log("BondingCurveFactory ownership transferred to CreatorTokenFactory");

        creatorCoinFactory.transferOwnership(address(creatorTokenFactory));
        console.log("CreatorCoinFactory ownership transferred to CreatorTokenFactory");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("BondingCurve Implementation:", address(bondingCurveImpl));
        console.log("CreatorTokenFactory:", address(creatorTokenFactory));
        console.log("BondingCurveFactory:", address(bondingCurveFactory));
        console.log("CreatorCoinFactory:", address(creatorCoinFactory));
    }
}
