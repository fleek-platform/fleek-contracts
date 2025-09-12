// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC1363 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";

/// @title Base Character Token
/// @notice ERC20 token with permit, burn, and ERC1363 functionality
/// @dev Fixed supply of 1B tokens
contract BaseCharacterToken is ERC20, ERC20Permit, ERC20Burnable, ERC1363 {
    /// @notice Thrown when recipient address is zero
    error InvalidRecipient();

    /// @notice Deploys token with entire supply to recipient
    /// @param recipient Address receiving initial 100M token supply
    constructor(address recipient, string memory name, string memory symbol)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        require(recipient != address(0), InvalidRecipient());
        _mint(recipient, 1_000_000_000e18);
    }
}
