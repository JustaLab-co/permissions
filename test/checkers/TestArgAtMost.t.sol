// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { ArgAtMost } from "src/checkers/ArgAtMost.sol";

contract TestArgAtMost is Test {

    bytes4 internal constant TRANSFER = 0xa9059cbb; // transfer(address,uint256)
    bytes4 internal constant APPROVE = 0x095ea7b3; // approve(address,uint256)
    uint256 internal constant CAP = 200e6; // 200 USDC
    address internal constant WALLET = address(0x3A11E7);
    address internal constant TO = address(0x1A4D);

    ArgAtMost internal template;
    ArgAtMost internal checker;

    function setUp() public {
        template = new ArgAtMost();
        checker = ArgAtMost(LibClone.clone(address(template), abi.encode(TRANSFER, uint256(1), CAP)));
    }

    function _check(ArgAtMost c, bytes memory data) internal view returns (bool) {
        return c.canExecute(bytes32(0), WALLET, address(0), address(0), 0, data);
    }

    function test_AllowsExactlyTheCap() public view {
        assertTrue(_check(checker, abi.encodeWithSelector(TRANSFER, TO, CAP)));
    }

    function test_RefusesOneOverTheCap() public view {
        assertFalse(_check(checker, abi.encodeWithSelector(TRANSFER, TO, CAP + 1)));
    }

    function test_RefusesAnotherFunction() public view {
        assertFalse(_check(checker, abi.encodeWithSelector(APPROVE, TO, 1)));
    }

    function test_RefusesCalldataTooShortForTheSlot() public view {
        assertFalse(_check(checker, abi.encodePacked(TRANSFER, bytes32(uint256(uint160(TO))))));
    }

    function test_TemplateCalledDirectlyRefusesEverything() public view {
        assertFalse(_check(template, abi.encodeWithSelector(TRANSFER, TO, 1)));
    }

    function testFuzz_PassesOnlyAtOrUnderTheCap(uint256 amount) public view {
        assertEq(_check(checker, abi.encodeWithSelector(TRANSFER, TO, amount)), amount <= CAP);
    }

}
