// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { FLKToken } from "../../src/token/FLKToken.sol";

contract FLKTest is Test {
    FLKToken public token;
    // Anvil Provided address
    address public recipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        token = new FLKToken(recipient);
    }

    function test_RecipientBalance() public view {
        uint256 recipientBalance = token.balanceOf(recipient);
        assertEq(recipientBalance, 100_000_000 * (10 ** 18));
    }

    function test_EnsureCorrectSupply() public view {
        assertEq(token.totalSupply(), 100_000_000 * (10 ** 18));
    }

    function test_RevertOnZeroAddress() public {
        vm.expectRevert(FLKToken.InvalidRecipient.selector);
        new FLKToken(address(0));
    }
}
