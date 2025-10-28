// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";

contract DeployFactoryAndToken is Script {
    function run() external {
        // address creator = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
        // string memory name = "Test Token";
        // string memory symbol = "TEST";
        //
        // uint64 vestingStart = uint64(block.timestamp);
        // uint64 vestingDuration = 365 days;
        // uint64 cliffDuration = 30 days;
        //
        // FactoryConfig config;
        // CharacterTokenFactory factory;
        //
        // vm.startBroadcast();
        // config = new FactoryConfig();
        // factory =
        //     new CharacterTokenFactory(0x5719061AD5052C1f2E4c942c68F35935adD31f7E, address(config));
        // vm.stopBroadcast();
        //
        // console.log("Factory deployed at:", address(factory));
        //
        // vm.startBroadcast();
        // factory.deployNew(creator, name, symbol, vestingStart, vestingDuration, cliffDuration);
        // vm.stopBroadcast();
        //
        // console.log("Token deployed for creator:", creator);
    }
}
