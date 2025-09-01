// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import { FLKToken } from "../src/token/FLKToken.sol";

contract DeployFLK is Script {
    address FOUNDATION_MULTISIG = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;

    function run() public {
        bytes32 salt = keccak256(abi.encodePacked("FLK_TOKEN", "v1.0"));

        address predicted = vm.computeCreate2Address(
            salt,
            keccak256(
                abi.encodePacked(type(FLKToken).creationCode, abi.encode(FOUNDATION_MULTISIG))
            )
        );

        console.log("Predicted address:", predicted);

        vm.startBroadcast();
        FLKToken token = new FLKToken{ salt: salt }(FOUNDATION_MULTISIG);
        vm.stopBroadcast();

        require(address(token) == predicted, "Address mismatch");
    }
}
