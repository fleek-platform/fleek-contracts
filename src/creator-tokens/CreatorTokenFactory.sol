// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { BondingCurve } from "./BondingCurve.sol";
import { LinearCurveMathV4 } from "./lib/LinearCurveMath.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract CharacterTokenFactory is AccessControlDefaultAdminRules {
    uint8 constant FLK_DECIMALS = 18;
    uint8 constant CREATOR_COIN_DECIMALS = 18;
    address constant FLK = 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;

    address foundationMultisig = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;
    address fanPoolWallet = 0x491193C8C2BA55503dBf83eB608E69E93b9Ba96a;

    uint256 creatorCoinSupply = 1_000_000e18;

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
    event CreatorAllocationUpdated(uint256 newAllocation);

    error TotalAllocationExceedsSupply(uint256 total, uint256 supply);
    error GraduationThresholdTooLow(uint256 threshold, uint256 projected);
    error BasePriceZero();
    error InvalidCurveConfiguration();
    error TokenNameExists();
    error TokenTransferFailed();

    constructor() AccessControlDefaultAdminRules(3 days, foundationMultisig) { }

    mapping(string => bool) public tokenNames;

    function deployNew(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) public {
        require(!tokenNames[_name], TokenNameExists());
        tokenNames[_name] = true;

        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol, creatorCoinSupply);

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

        require(creatorCoin.transfer(foundationMultisig, creatorFundAllocation), TokenTransferFailed());
        require(creatorCoin.transfer(address(bondingCurve), bondingCurveAllocation), TokenTransferFailed());
        require(creatorCoin.transfer(address(creatorVesting), creatorAllocation), TokenTransferFailed());
        require(creatorCoin.transfer(fanPoolWallet, fanPoolAllocation), TokenTransferFailed());

        emit TokenDeployed({ newToken: address(creatorCoin), bondingCurve: address(bondingCurve) });
    }

    function previewAccumulation() external view returns (uint256) {
        return basePrice * (bondingCurveAllocation / 2) + graduationThreshold;
    }

    function updateGraduationThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 finalPriceValue = LinearCurveMathV4.finalPrice(
            newThreshold, bondingCurveAllocation / 2, basePrice, CREATOR_COIN_DECIMALS, FLK_DECIMALS
        );

        uint256 slopeValue = LinearCurveMathV4.slope(
            finalPriceValue,
            basePrice,
            bondingCurveAllocation / 2,
            CREATOR_COIN_DECIMALS,
            FLK_DECIMALS
        );

        uint256 projectedAccumulation = LinearCurveMathV4.calculateBuyCost(
            bondingCurveAllocation / 2,
            0,
            basePrice,
            slopeValue,
            CREATOR_COIN_DECIMALS,
            FLK_DECIMALS
        );

        if (projectedAccumulation < newThreshold) {
            revert GraduationThresholdTooLow(newThreshold, projectedAccumulation);
        }

        graduationThreshold = newThreshold;
        emit GraduationThresholdUpdated({ newThreshold: newThreshold });
    }

    function updateBasePrice(uint256 newBasePrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newBasePrice == 0) revert BasePriceZero();

        uint256 finalPriceValue = LinearCurveMathV4.finalPrice(
            graduationThreshold,
            bondingCurveAllocation / 2,
            newBasePrice,
            CREATOR_COIN_DECIMALS,
            FLK_DECIMALS
        );

        uint256 slopeValue = LinearCurveMathV4.slope(
            finalPriceValue,
            newBasePrice,
            bondingCurveAllocation / 2,
            CREATOR_COIN_DECIMALS,
            FLK_DECIMALS
        );

        uint256 projectedAccumulation = LinearCurveMathV4.calculateBuyCost(
            bondingCurveAllocation / 2,
            0,
            newBasePrice,
            slopeValue,
            CREATOR_COIN_DECIMALS,
            FLK_DECIMALS
        );

        if (projectedAccumulation < graduationThreshold) {
            revert InvalidCurveConfiguration();
        }

        basePrice = newBasePrice;
        emit BasePriceUpdated({ newBasePrice: newBasePrice });
    }

    function updateBondingCurveAllocation(uint256 newAllocation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 total =
            newAllocation + creatorAllocation + creatorFundAllocation + fanPoolAllocation;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        bondingCurveAllocation = newAllocation;
        emit BondingCurveAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateCreatorFundAllocation(uint256 newAllocation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 total =
            bondingCurveAllocation + creatorAllocation + newAllocation + fanPoolAllocation;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        creatorFundAllocation = newAllocation;
        emit CreatorFundAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateFanPoolAllocation(uint256 newAllocation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 total =
            bondingCurveAllocation + creatorAllocation + creatorFundAllocation + newAllocation;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        fanPoolAllocation = newAllocation;
        emit FanPoolAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateCreatorAllocation(uint256 newAllocation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 total =
            bondingCurveAllocation + newAllocation + creatorFundAllocation + fanPoolAllocation;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        creatorAllocation = newAllocation;
        emit CreatorAllocationUpdated({ newAllocation: newAllocation });
    }
}
