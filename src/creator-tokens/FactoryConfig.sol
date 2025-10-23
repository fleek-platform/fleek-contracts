// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

contract FactoryConfig {
    struct Allocations {
        uint256 bondingCurve;
        uint256 creator;
        uint256 creatorFund;
        uint256 fanPool;
    }

    struct BondingCurveCriteria {
        uint256 graduationThreshold;
        uint256 basePrice;
    }

    struct Wallets {
        address foundation;
        address fanPoolController;
    }

    Allocations public allocations = Allocations({
        bondingCurve: 450_000e18, creator: 250_000e18, creatorFund: 50_000e18, fanPool: 250_000e18
    });

    BondingCurveCriteria public bondingCurveCriteria =
        BondingCurveCriteria({ graduationThreshold: 20_675e18, basePrice: 1e15 });

    Wallets public wallets = Wallets({
        foundation: address(0x5719061AD5052C1f2E4c942c68F35935adD31f7E),
        fanPoolController: 0x491193C8C2BA55503dBf83eB608E69E93b9Ba96a
    });

    address public constant FLK = 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;

    uint256 public constant creatorCoinSupply = 1_000_000e18;
}
