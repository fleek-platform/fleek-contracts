// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { ERC20 } from "solady/tokens/ERC20.sol";
import { Config } from "../libraries/Config.sol";

/*
*  @title Creator Coin
*  @notice Gas-optimized ERC20 token with permit and burn functionality
*/
contract CreatorCoin is ERC20 {
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _mint(msg.sender, Config.CREATOR_COIN_SUPPLY);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) public virtual {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }
}
