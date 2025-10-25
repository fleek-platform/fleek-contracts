// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BondingCurve } from "./BondingCurve.sol";
import { FactoryConfig } from "./lib/FactoryConfig.sol";

/// @title Bonding Curve Factory
/// @notice Factory contract for deploying linear bonding curves with graduation mechanism
/// @dev Only the owner (CreatorTokenFactory) can deploy bonding curves
contract BondingCurveFactory is Ownable {
    /// @notice Initializes the factory with the specified owner
    /// @param _owner Address that will own this factory (typically CreatorTokenFactory)
    constructor(address _owner) Ownable(_owner) { }

    /// @notice Deploys a new bonding curve for a creator token
    /// @dev The bonding curve receives half of BONDING_CURVE_ALLOCATION to sell on the curve.
    ///      The other half remains in the bonding curve contract and is deposited into the
    ///      Uniswap V4 liquidity pool when the curve graduates at the graduation threshold.
    /// @param _creator Address of the creator who will receive swap fees
    /// @param _creatorToken Address of the creator token (ERC20)
    /// @param _vestingWallet Address of the vesting wallet for fee calculations
    /// @return bondingCurve The deployed BondingCurve contract
    function deploy(address _creator, address _creatorToken, address _vestingWallet)
        external
        onlyOwner
        returns (BondingCurve)
    {
        BondingCurve bondingCurve = new BondingCurve(
            _creator,
            _creatorToken,
            FactoryConfig.GRADUATION_THRESHOLD,
            FactoryConfig.BASE_PRICE,
            FactoryConfig.BONDING_CURVE_ALLOCATION / 2,
            _vestingWallet
        );

        return bondingCurve;
    }
}
