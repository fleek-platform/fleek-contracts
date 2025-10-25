// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { VestingWalletCliff } from "@openzeppelin/contracts/finance/VestingWalletCliff.sol";
import { VestingWallet } from "@openzeppelin/contracts/finance/VestingWallet.sol";

contract CreatorVesting is VestingWalletCliff {
    constructor(address _beneficiary, uint64 _start, uint64 _duration, uint64 _cliffDuration)
        VestingWallet(_beneficiary, _start, _duration)
        VestingWalletCliff(_cliffDuration)
    { }
}
