// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "../tokens/CreatorCoin.sol";
import { CreatorVesting } from "../tokens/CreatorVesting.sol";
import { BondingCurve } from "../curve/BondingCurve.sol";
import { BondingCurveFactory } from "./BondingCurveFactory.sol";
import { CreatorCoinFactory } from "./CreatorCoinFactory.sol";

/**
 * @title CreatorTokenFactory
 * @notice Orchestrates deployment of creator token ecosystems with bonding curves and vesting
 * @dev Delegates to specialized factories for modular upgrades
 */
contract CreatorTokenFactory is Ownable2Step {
    /**
     * @notice Factory for deploying bonding curve contracts
     */
    BondingCurveFactory public bondingCurveFactory;

    /**
     * @notice Factory for deploying creator coins and vesting contracts
     */
    CreatorCoinFactory public creatorCoinFactory;

    /**
     * @notice Registry preventing duplicate token names
     */
    mapping(string => bool) public tokenNames;

    /**
     * @notice Maps creator tokens to their authorized bonding curves
     * @dev Used by UniversalAntiFlipFeeHook to verify registration authorization
     */
    mapping(address => address) public bondingCurveFor;

    /**
     * @notice Emitted when a new creator token ecosystem is deployed
     * @param newToken Address of the creator coin
     * @param bondingCurve Address of the bonding curve
     * @param vestingContract Address of the vesting wallet
     */
    event TokenDeployed(address newToken, address bondingCurve, address vestingContract);

    /**
     * @notice Thrown when attempting to deploy with an existing token name
     */
    error TokenNameExists();

    /**
     * @notice Initializes the factory with foundation ownership and sub-factories
     * @param _foundation Address receiving ownership (typically foundation multisig)
     * @param _bondingCurveFactory Address of the bonding curve factory
     * @param _creatorCoinFactory Address of the creator coin factory
     */
    constructor(address _foundation, address _bondingCurveFactory, address _creatorCoinFactory)
        Ownable(_foundation)
    {
        bondingCurveFactory = BondingCurveFactory(_bondingCurveFactory);
        creatorCoinFactory = CreatorCoinFactory(_creatorCoinFactory);
    }

    /**
     * @notice Deploys a complete creator token ecosystem
     * @param _name Token name (must be unique)
     * @param _symbol Token symbol
     * @param _vestingStart Timestamp when vesting begins
     * @param _vestingDuration Total vesting period in seconds
     * @param _cliffDuration Cliff period in seconds before vesting starts
     */
    function deployNew(
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) public {
        require(!tokenNames[_name], TokenNameExists());
        tokenNames[_name] = true;

        (CreatorCoin creatorCoin, CreatorVesting creatorVesting) = creatorCoinFactory.deploy(
            msg.sender, _name, _symbol, _vestingStart, _vestingDuration, _cliffDuration
        );

        BondingCurve bondingCurve =
            bondingCurveFactory.deploy(msg.sender, address(creatorCoin), address(creatorVesting));

        creatorCoinFactory.transferToBondingCurve(address(creatorCoin), address(bondingCurve));

        // Register bonding curve for this token (used by UniversalAntiFlipFeeHook for authorization)
        bondingCurveFor[address(creatorCoin)] = address(bondingCurve);

        emit TokenDeployed({
            newToken: address(creatorCoin),
            bondingCurve: address(bondingCurve),
            vestingContract: address(creatorVesting)
        });
    }

    /**
     * @notice Updates the bonding curve factory implementation
     * @dev Allows upgrading bonding curve logic for future deployments
     * @param _bondingCurveFactory New bonding curve factory address
     */
    function setBondingCurveFactory(address _bondingCurveFactory) external onlyOwner {
        bondingCurveFactory = BondingCurveFactory(_bondingCurveFactory);
    }

    /**
     * @notice Updates the creator coin factory implementation
     * @dev Allows upgrading token/vesting logic for future deployments
     * @param _creatorCoinFactory New creator coin factory address
     */
    function setCreatorCoinFactory(address _creatorCoinFactory) external onlyOwner {
        creatorCoinFactory = CreatorCoinFactory(_creatorCoinFactory);
    }
}
