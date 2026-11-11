// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { ArgIn } from "src/checkers/ArgIn.sol";
import { CheckerLib } from "src/checkers/CheckerLib.sol";

contract TestArgIn is Test {

    bytes4 internal constant TRANSFER = 0xa9059cbb; // transfer(address,uint256)
    bytes4 internal constant APPROVE = 0x095ea7b3; // approve(address,uint256)

    address internal constant LANDLORD = address(0x1A4D);
    address internal constant ACCOUNTANT = address(0xACC7);
    address internal constant STRANGER = address(0xBAD);
    address internal constant WALLET = address(0x3A11E7);

    ArgIn internal template;

    function setUp() public {
        template = new ArgIn();
    }

    function _clone(bytes4 selector, uint256 slot, address[] memory allowed) internal returns (ArgIn) {
        bytes32[] memory values = new bytes32[](allowed.length);
        for (uint256 i; i < allowed.length; ++i) {
            values[i] = bytes32(uint256(uint160(allowed[i])));
        }
        return ArgIn(LibClone.clone(address(template), abi.encode(selector, slot, values)));
    }

    function _list(address a) internal pure returns (address[] memory l) {
        l = new address[](1);
        l[0] = a;
    }

    function _list(address a, address b) internal pure returns (address[] memory l) {
        l = new address[](2);
        l[0] = a;
        l[1] = b;
    }

    function _check(ArgIn checker, address account, bytes memory data) internal view returns (bool) {
        return checker.canExecute(bytes32(0), account, address(0), address(0), 0, data);
    }

    function test_AllowsAValueInTheList() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(LANDLORD, ACCOUNTANT));
        assertTrue(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, LANDLORD, 100)));
        assertTrue(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, ACCOUNTANT, 100)));
    }

    function test_RefusesAValueNotInTheList() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(LANDLORD, ACCOUNTANT));
        assertFalse(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, STRANGER, 100)));
    }

    function test_ReadsTheConfiguredSlot() public {
        // Slot 1 of transfer is the amount, so the list holds amounts here.
        ArgIn checker = _clone(TRANSFER, 1, _list(address(uint160(100))));
        assertTrue(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, STRANGER, 100)));
        assertFalse(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, LANDLORD, 101)));
    }

    function test_RefusesAnotherFunctionEvenWhenTheValueMatches() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(LANDLORD));
        assertFalse(_check(checker, WALLET, abi.encodeWithSelector(APPROVE, LANDLORD, 100)));
    }

    function test_RefusesCalldataTooShortForTheSlot() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(LANDLORD));
        assertFalse(_check(checker, WALLET, abi.encodePacked(TRANSFER)));
        assertFalse(_check(checker, WALLET, ""));
    }

    function test_RefusesAnAddressWithDirtyHighBits() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(LANDLORD));
        bytes memory data =
            abi.encodePacked(TRANSFER, bytes32(uint256(uint160(LANDLORD)) | (uint256(1) << 200)), uint256(100));
        assertFalse(_check(checker, WALLET, data));
    }

    function test_AccountSentinelMeansTheWalletRunningTheCall() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(CheckerLib.ACCOUNT));
        assertTrue(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, WALLET, 100)));
        assertFalse(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, STRANGER, 100)));
    }

    function test_OneAccountCloneServesEveryWallet() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(CheckerLib.ACCOUNT));
        address otherWallet = address(0x0DD);
        assertTrue(_check(checker, otherWallet, abi.encodeWithSelector(TRANSFER, otherWallet, 1)));
        assertFalse(_check(checker, otherWallet, abi.encodeWithSelector(TRANSFER, WALLET, 1)));
    }

    function test_TheSentinelItselfIsNotAnAllowedRecipient() public {
        ArgIn checker = _clone(TRANSFER, 0, _list(CheckerLib.ACCOUNT));
        assertFalse(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, CheckerLib.ACCOUNT, 100)));
    }

    function test_TemplateCalledDirectlyRefusesEverything() public view {
        assertFalse(_check(template, WALLET, abi.encodeWithSelector(TRANSFER, LANDLORD, 100)));
    }

    function testFuzz_OnlyListedRecipientsPass(address recipient, uint256 amount) public {
        ArgIn checker = _clone(TRANSFER, 0, _list(LANDLORD, ACCOUNTANT));
        bool expected = recipient == LANDLORD || recipient == ACCOUNTANT;
        assertEq(_check(checker, WALLET, abi.encodeWithSelector(TRANSFER, recipient, amount)), expected);
    }

}
