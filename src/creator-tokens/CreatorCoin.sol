// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title Creator Coin
/// @notice Implementation ERC20 token with permit and burn
/// @dev Fixed supply of 1 million tokens
contract CreatorCoin is ERC20, ERC20Permit, ERC20Burnable {
    constructor(string memory _name, string memory _symbol, uint256 supply)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {
        _mint(msg.sender, supply);
    }
}
