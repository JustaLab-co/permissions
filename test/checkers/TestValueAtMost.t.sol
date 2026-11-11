// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { ValueAtMost } from "src/checkers/ValueAtMost.sol";

contract TestValueAtMost is Test {

    bytes4 internal constant EMPTY = 0xe0e0e0e0; // plain ETH send
    bytes4 internal constant DEPOSIT = 0xd0e30db0; // deposit()
    uint256 internal constant CAP = 0.1 ether;
    address internal constant WALLET = address(0x3A11E7);

    ValueAtMost internal template;

    function setUp() public {
        template = new ValueAtMost();
    }

    function _clone(bytes4 selector) internal returns (ValueAtMost) {
        return ValueAtMost(LibClone.clone(address(template), abi.encode(selector, CAP)));
    }

    function _check(ValueAtMost c, uint256 value, bytes memory data) internal view returns (bool) {
        return c.canExecute(bytes32(0), WALLET, address(0), address(0), value, data);
    }

    function test_PlainSendAllowsExactlyTheCap() public {
        ValueAtMost checker = _clone(EMPTY);
        assertTrue(_check(checker, CAP, ""));
        assertFalse(_check(checker, CAP + 1, ""));
    }

    function test_FunctionCallAllowsExactlyTheCap() public {
        ValueAtMost checker = _clone(DEPOSIT);
        assertTrue(_check(checker, CAP, abi.encodeWithSelector(DEPOSIT)));
        assertFalse(_check(checker, CAP + 1, abi.encodeWithSelector(DEPOSIT)));
    }

    function test_RefusesAnotherFunction() public {
        ValueAtMost checker = _clone(DEPOSIT);
        assertFalse(_check(checker, 0, ""));
        assertFalse(_check(checker, 0, abi.encodeWithSignature("withdraw(uint256)", 1)));
    }

    function test_TemplateCalledDirectlyRefusesEverything() public view {
        assertFalse(_check(template, 0, ""));
    }

}
