// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { BondingCurve } from "../curve/BondingCurve.sol";
import { Config } from "../libraries/Config.sol";

/// @title Bonding Curve Factory
/// @notice Factory contract for deploying linear bonding curves with graduation mechanism
/// @dev Only the owner (CreatorTokenFactory) can deploy bonding curves
/// @dev Uses minimal proxy clones (EIP-1167) for gas-efficient deployments
contract BondingCurveFactory is Ownable {
    address public immutable implementation;

    /// @notice Initializes the factory with the specified owner and implementation
    /// @param _owner Address that will own this factory (typically CreatorTokenFactory)
    /// @param _implementation Address of the BondingCurve implementation contract
    constructor(address _owner, address _implementation) Ownable(_owner) {
        implementation = _implementation;
    }

    /// @notice Deploys a new bonding curve for a creator token using clone pattern
    /// @dev The bonding curve receives half of BONDING_CURVE_ALLOCATION to sell on the curve.
    ///      The other half remains in the bonding curve contract and is deposited into the
    ///      Uniswap V4 liquidity pool when the curve graduates at the graduation threshold.
    /// @param _creator Address of the creator who will receive swap fees
    /// @param _creatorToken Address of the creator token (ERC20)
    /// @param _vestingWallet Address of the vesting wallet for fee calculations
    /// @return bondingCurve The deployed BondingCurve clone
    function deploy(address _creator, address _creatorToken, address _vestingWallet)
        external
        onlyOwner
        returns (BondingCurve)
    {
        address clone = Clones.clone(implementation);

        BondingCurve(clone).initialize(
            _creator,
            _creatorToken,
            Config.GRADUATION_THRESHOLD,
            Config.BASE_PRICE,
            Config.BONDING_CURVE_ALLOCATION / 2,
            _vestingWallet
        );

        return BondingCurve(clone);
    }
}
