// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BaseCharacterToken } from "./BaseToken.sol";

contract CharacterTokenFactory {
    function deployNewCharacterToken(string memory name, string memory symbol) external {
        BaseCharacterToken newToken = new BaseCharacterToken(address(this), name, symbol);
        newToken.approve(address(this), 1_000_000_000e18);

        // TODO: add sablier lockup

        // TODO: deploy LP with custom bonding curve hook

        // TODO: transfer remaining tokens to treasury
    }
}
