// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { BondingCurve } from "./BondingCurve.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract CharacterTokenFactory is AccessControlDefaultAdminRules {
    address constant FLK = 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;

    address FOUNDATION_MULTISIG = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;
    address fanPoolWallet = 0x491193C8C2BA55503dBf83eB608E69E93b9Ba96a;

    uint256 graduationThreshold = 20_675e18; // Amount in FLK
    uint256 basePrice = 1e15;

    uint256 bondingCurveAllocation = 450_000e18;
    uint256 creatorAllocation = 250_000e18;
    uint256 creatorFundAllocation = 50_000e18;
    uint256 fanPoolAllocation = 250_000e18;

    event TokenDeployed(address newToken, address bondingCurve);
    event GraduationThresholdUpdated(uint256 newThreshold);
    event BondingCurveAllocationUpdated(uint256 newAllocation);
    event BasePriceUpdated(uint256 newBasePrice);
    event CreatorFundAllocationUpdated(uint256 newAllocation);
    event FanPoolWalletUpdated(address newWallet);
    event FanPoolAllocationUpdated(uint256 newAllocation);

    constructor() AccessControlDefaultAdminRules(3 days, FOUNDATION_MULTISIG) { }

    // check that token name doesnt already exist
    mapping(string => bool) public tokenNames;

    function deployNew(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) public {
        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol);

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);

        BondingCurve bondingCurve = new BondingCurve(
            _creator,
            FLK,
            address(creatorCoin),
            graduationThreshold,
            basePrice,
            bondingCurveAllocation / 2
        );

        creatorCoin.transfer(FOUNDATION_MULTISIG, creatorFundAllocation);
        creatorCoin.transfer(address(bondingCurve), bondingCurveAllocation);
        creatorCoin.transfer(address(creatorVesting), creatorAllocation);
        creatorCoin.transfer(fanPoolWallet, fanPoolAllocation);

        emit TokenDeployed({ newToken: address(creatorCoin), bondingCurve: address(bondingCurve) });
    }

    function updateGraduationThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        graduationThreshold = newThreshold;
        emit GraduationThresholdUpdated({ newThreshold: newThreshold });
    }

    function updateBondingCurveAllocation(uint256 newAllocation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bondingCurveAllocation = newAllocation;
        emit BondingCurveAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateBasePrice(uint256 newBasePrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        basePrice = newBasePrice;
        emit BasePriceUpdated({ newBasePrice: newBasePrice });
    }

    function updateCreatorFundAllocation(uint256 newAllocation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        creatorFundAllocation = newAllocation;
        emit CreatorFundAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateFanPoolWallet(address newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fanPoolWallet = newWallet;
        emit FanPoolWalletUpdated({ newWallet: newWallet });
    }

    function updateFanPoolAllocation(uint256 newAllocation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fanPoolAllocation = newAllocation;
        emit FanPoolAllocationUpdated({ newAllocation: newAllocation });
    }
}
