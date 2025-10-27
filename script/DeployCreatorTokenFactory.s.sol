// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/curve/BondingCurve.sol";
import { BondingCurveFactory } from "../src/creator-tokens/core/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../src/creator-tokens/core/CreatorCoinFactory.sol";
import { Config } from "../src/creator-tokens/libraries/Config.sol";

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

        // 3. Deploy main factory (foundation address depends on chain ID)
        CreatorTokenFactory creatorTokenFactory = new CreatorTokenFactory(
            Config.FOUNDATION(), address(bondingCurveFactory), address(creatorCoinFactory)
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
