// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { ERC20 } from "solady/tokens/ERC20.sol";
import { Config } from "../libraries/Config.sol";
import { BaseUniswapDeployments } from "../libraries/BaseUniswapDeployments.sol";

/*
*  @title Creator Coin
*  @notice Gas-optimized ERC20 token with permit and burn functionality
*/
contract CreatorCoin is ERC20 {
    address public immutable POOL_MANAGER;
    address public immutable FACTORY;

    string private _name;
    string private _symbol;

    address public bondingCurve;
    address public hook;

    mapping(address => uint256) public transferLockedUntil;

    error TransfersLocked();

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        FACTORY = msg.sender;
        POOL_MANAGER = BaseUniswapDeployments.POOL_MANAGER();
        _mint(msg.sender, Config.CREATOR_COIN_SUPPLY);
    }

    /**
     * @notice Locks transfers for a user until specified timestamp
     * @dev Only callable by bonding curve or hook
     * @param user Address to lock transfers for
     * @param timestamp Timestamp until which transfers are locked
     */
    function lockTransfers(address user, uint256 timestamp) external {
        require(msg.sender == bondingCurve || msg.sender == hook, "Unauthorized");
        transferLockedUntil[user] = timestamp;
    }

    /**
     * @notice Sets the bonding curve and hook addresses
     * @dev Can only be called once by the factory
     * @param bondingCurve_ Address of the bonding curve
     * @param hook_ Address of the universal hook
     */
    function setAddresses(address bondingCurve_, address hook_) external {
        require(bondingCurve == address(0), "Already set");
        require(msg.sender == FACTORY, "Only factory");
        bondingCurve = bondingCurve_;
        hook = hook_;
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

    /**
     * @notice Hook called before any token transfer
     * @dev Blocks peer-to-peer transfers while locked
     *      Can still interact with Uniswap Pool Manager and bonding curve during this period
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (from == address(0) || to == address(0) || to == POOL_MANAGER || to == bondingCurve) {
            return;
        }

        if (transferLockedUntil[from] > block.timestamp) {
            revert TransfersLocked();
        }
    }
}
