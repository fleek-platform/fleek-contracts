// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "../tokens/CreatorCoin.sol";
import { CreatorVesting } from "../tokens/CreatorVesting.sol";
import { BondingCurve } from "../curve/BondingCurve.sol";
import { BondingCurveFactory } from "./BondingCurveFactory.sol";
import { CreatorCoinFactory } from "./CreatorCoinFactory.sol";
import { Config } from "../libraries/Config.sol";

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
     * @notice Initializes the factory with foundation ownership and sub-factories
     * @param _bondingCurveFactory Address of the bonding curve factory
     * @param _creatorCoinFactory Address of the creator coin factory
     */
    constructor(address _bondingCurveFactory, address _creatorCoinFactory)
        Ownable(Config.COIN_DEPLOYMENT_AUTHORIZER())
    {
        bondingCurveFactory = BondingCurveFactory(_bondingCurveFactory);
        creatorCoinFactory = CreatorCoinFactory(_creatorCoinFactory);
    }

    /**
     * @notice Deploys a complete creator token ecosystem
     * @param _creator Token creator
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _vestingStart Timestamp when vesting begins
     */
    function deployNew(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart
    ) external onlyOwner {
        (CreatorCoin creatorCoin, CreatorVesting creatorVesting) = creatorCoinFactory.deploy(
            _creator, _name, _symbol, _vestingStart, Config.VESTING_DURATION, Config.VESTING_CLIFF
        );

        BondingCurve bondingCurve =
            bondingCurveFactory.deploy(_creator, address(creatorCoin), address(creatorVesting));

        address hook = bondingCurveFactory.universalHook();
        creatorCoinFactory.setTokenAddresses(address(creatorCoin), address(bondingCurve), hook);

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
