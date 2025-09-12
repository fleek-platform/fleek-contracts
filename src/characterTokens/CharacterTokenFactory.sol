// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BaseCharacterToken } from "./BaseToken.sol";

contract CharacterTokenFactory {
    function deployNewCharacterToken(string memory name, string memory symbol) external {
        new BaseCharacterToken(msg.sender, name, symbol);
    }
}
