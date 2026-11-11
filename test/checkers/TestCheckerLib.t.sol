// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { CheckerLib } from "src/checkers/CheckerLib.sol";

contract CheckerLibHarness {

    function selectorOf(bytes calldata data) external pure returns (bytes4) {
        return CheckerLib.selectorOf(data);
    }

    function wordAt(bytes calldata data, uint256 slot) external pure returns (bool found, bytes32 word) {
        return CheckerLib.wordAt(data, slot);
    }

}

contract TestCheckerLib is Test {

    CheckerLibHarness internal lib;

    function setUp() public {
        lib = new CheckerLibHarness();
    }

    function test_SelectorIsFirstFourBytes() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(0xBEEF), 1);
        assertEq(lib.selectorOf(data), bytes4(0xa9059cbb));
    }

    function test_EmptyCalldataUsesTheManagersEmptySelector() public view {
        assertEq(lib.selectorOf(""), bytes4(0xe0e0e0e0));
    }

    function test_CalldataShorterThanASelectorUsesTheEmptySelector() public view {
        assertEq(lib.selectorOf(hex"a905"), bytes4(0xe0e0e0e0));
    }

    function test_ReadsEachArgumentSlot() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(0xBEEF), 42);

        (bool found0, bytes32 word0) = lib.wordAt(data, 0);
        (bool found1, bytes32 word1) = lib.wordAt(data, 1);

        assertTrue(found0);
        assertEq(word0, bytes32(uint256(0xBEEF)));
        assertTrue(found1);
        assertEq(word1, bytes32(uint256(42)));
    }

    function test_SlotPastTheEndIsNotFound() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(0xBEEF), 42);
        (bool found,) = lib.wordAt(data, 2);
        assertFalse(found);
    }

    function test_PartialLastWordIsNotFound() public view {
        // Selector plus 31 bytes: slot 0 is cut short.
        bytes memory data = abi.encodePacked(bytes4(0xa9059cbb), bytes31(0));
        (bool found,) = lib.wordAt(data, 0);
        assertFalse(found);
    }

    function test_HugeSlotIsNotFoundInsteadOfOverflowing() public view {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(0xBEEF), 42);
        (bool found,) = lib.wordAt(data, type(uint256).max);
        assertFalse(found);
    }

}
