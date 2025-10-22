// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { BondingCurve } from "./BondingCurve.sol";

contract CharacterTokenFactory is Ownable2Step {
    struct Allocations {
        uint256 bondingCurve;
        uint256 creator;
        uint256 creatorFund;
        uint256 fanPool;
    }

    struct Decimals {
        uint8 flk;
        uint8 creatorCoins;
    }

    struct BondingCurveCriteria {
        uint256 graduationThreshold;
        uint256 basePrice;
    }

    struct Wallets {
        address foundation;
        address fanPoolController;
    }

    Allocations allocations = Allocations({
        bondingCurve: 450_000e18, creator: 250_000e18, creatorFund: 50_000e18, fanPool: 250_000e18
    });

    Decimals tokenDecimals = Decimals({ flk: 18, creatorCoins: 18 });

    BondingCurveCriteria bondingCurveCriteria =
        BondingCurveCriteria({ graduationThreshold: 20_675e18, basePrice: 1e15 });

    Wallets wallets = Wallets({
        foundation: address(0), fanPoolController: 0x491193C8C2BA55503dBf83eB608E69E93b9Ba96a
    });

    address constant FLK = 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;

    uint256 creatorCoinSupply = 1_000_000e18;

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
    error ZeroThreshold();
    error ZeroAllocation();

    constructor(address _foundation) Ownable(_foundation) {
        wallets.foundation = _foundation;
    }

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
            bondingCurveCriteria.graduationThreshold,
            bondingCurveCriteria.basePrice,
            allocations.bondingCurve / 2
        );

        require(
            creatorCoin.transfer(wallets.foundation, allocations.creatorFund), TokenTransferFailed()
        );
        require(
            creatorCoin.transfer(address(bondingCurve), allocations.bondingCurve),
            TokenTransferFailed()
        );
        require(
            creatorCoin.transfer(address(creatorVesting), allocations.creator),
            TokenTransferFailed()
        );
        require(
            creatorCoin.transfer(wallets.fanPoolController, allocations.fanPool),
            TokenTransferFailed()
        );

        emit TokenDeployed({ newToken: address(creatorCoin), bondingCurve: address(bondingCurve) });
    }

    function updateBondingCurveAllocation(uint256 newAllocation) external onlyOwner {
        uint256 total =
            newAllocation + allocations.creator + allocations.creatorFund + allocations.fanPool;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        allocations.bondingCurve = newAllocation;
        emit BondingCurveAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateCreatorFundAllocation(uint256 newAllocation) external onlyOwner {
        uint256 total =
            allocations.bondingCurve + allocations.creator + newAllocation + allocations.fanPool;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        allocations.creatorFund = newAllocation;
        emit CreatorFundAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateFanPoolAllocation(uint256 newAllocation) external onlyOwner {
        uint256 total =
            allocations.bondingCurve + allocations.creator + allocations.creatorFund + newAllocation;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        allocations.fanPool = newAllocation;
        emit FanPoolAllocationUpdated({ newAllocation: newAllocation });
    }

    function updateCreatorAllocation(uint256 newAllocation) external onlyOwner {
        uint256 total =
            allocations.bondingCurve + newAllocation + allocations.creatorFund + allocations.fanPool;
        if (total > creatorCoinSupply) {
            revert TotalAllocationExceedsSupply(total, creatorCoinSupply);
        }
        allocations.creator = newAllocation;
        emit CreatorAllocationUpdated({ newAllocation: newAllocation });
    }
}
