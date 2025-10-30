// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "../tokens/CreatorCoin.sol";
import { CreatorVesting } from "../tokens/CreatorVesting.sol";
import { Config } from "../libraries/Config.sol";

/**
 * @title CreatorCoinFactory
 * @notice Deploys creator tokens and distributes initial allocations
 */
contract CreatorCoinFactory is Ownable {
    /**
     * @notice Thrown when token transfer fails during deployment
     */
    error TokenTransferFailed();

    constructor(address _owner) Ownable(_owner) { }

    /**
     * @notice Deploys creator coin and vesting contract with allocations
     * @param _creator Address receiving vested tokens
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _vestingStart Vesting start timestamp
     * @param _vestingDuration Total vesting period
     * @param _cliffDuration Cliff period before vesting starts
     * @return CreatorCoin deployed token, CreatorVesting deployed vesting contract
     */
    function deploy(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) external onlyOwner returns (CreatorCoin, CreatorVesting) {
        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol);

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);

        require(
            creatorCoin.transfer(
                Config.FOUNDATION(), Config.CREATOR_FUND_ALLOCATION + Config.FAN_POOL_ALLOCATION
            ),
            TokenTransferFailed()
        );
        require(
            creatorCoin.transfer(address(creatorVesting), Config.CREATOR_ALLOCATION),
            TokenTransferFailed()
        );

        return (creatorCoin, creatorVesting);
    }

    /**
     * @notice Transfers bonding curve allocation to deployed curve
     * @param _creatorCoin Token address
     * @param _bondingCurve Bonding curve address
     */
    function transferToBondingCurve(address _creatorCoin, address _bondingCurve)
        external
        onlyOwner
    {
        require(
            CreatorCoin(_creatorCoin).transfer(_bondingCurve, Config.BONDING_CURVE_ALLOCATION),
            TokenTransferFailed()
        );
    }
}
