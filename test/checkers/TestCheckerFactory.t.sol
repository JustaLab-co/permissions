// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test, Vm } from "forge-std/Test.sol";
import { ArgAtMost } from "src/checkers/ArgAtMost.sol";
import { ArgIn } from "src/checkers/ArgIn.sol";
import { CheckerFactory } from "src/checkers/CheckerFactory.sol";

contract TestCheckerFactory is Test {

    bytes4 internal constant TRANSFER = 0xa9059cbb;
    address internal constant WALLET = address(0x3A11E7);
    address internal constant TO = address(0x1A4D);

    CheckerFactory internal factory;
    ArgAtMost internal atMost;
    ArgIn internal argIn;

    function setUp() public {
        factory = new CheckerFactory();
        atMost = new ArgAtMost();
        argIn = new ArgIn();
    }

    function _cap(uint256 max) internal pure returns (bytes memory) {
        return abi.encode(TRANSFER, uint256(1), max);
    }

    function test_DeploysAtThePredictedAddress() public {
        address predicted = factory.predict(address(atMost), _cap(200e6));
        assertEq(predicted.code.length, 0);

        address deployed = factory.deploy(address(atMost), _cap(200e6));

        assertEq(deployed, predicted);
        assertGt(deployed.code.length, 0);
    }

    function test_TheCloneEnforcesItsOwnSettings() public {
        ArgAtMost checker = ArgAtMost(factory.deploy(address(atMost), _cap(200e6)));
        assertTrue(checker.canExecute(0, WALLET, address(0), TO, 0, abi.encodeWithSelector(TRANSFER, TO, 200e6)));
        assertFalse(checker.canExecute(0, WALLET, address(0), TO, 0, abi.encodeWithSelector(TRANSFER, TO, 200e6 + 1)));
    }

    function test_DeployingTheSameSettingsAgainReturnsTheSameCheckerWithoutReverting() public {
        address first = factory.deploy(address(atMost), _cap(200e6));

        vm.recordLogs();
        address second = factory.deploy(address(atMost), _cap(200e6));

        assertEq(second, first);
        assertEq(vm.getRecordedLogs().length, 0, "no deploy event the second time");
    }

    function test_AnnouncesANewChecker() public {
        address predicted = factory.predict(address(atMost), _cap(200e6));
        vm.expectEmit(address(factory));
        emit CheckerFactory.CheckerDeployed(address(atMost), predicted, _cap(200e6));
        factory.deploy(address(atMost), _cap(200e6));
    }

    function test_DifferentSettingsGiveADifferentChecker() public view {
        assertNotEq(factory.predict(address(atMost), _cap(200e6)), factory.predict(address(atMost), _cap(300e6)));
    }

    function test_DifferentTemplatesGiveADifferentChecker() public view {
        assertNotEq(factory.predict(address(atMost), _cap(200e6)), factory.predict(address(argIn), _cap(200e6)));
    }

    function test_AnyoneGetsTheSameAddressForTheSameSettings() public {
        vm.prank(address(0xA11CE));
        address alice = factory.deploy(address(atMost), _cap(200e6));
        vm.prank(address(0xB0B));
        address bob = factory.deploy(address(atMost), _cap(200e6));
        assertEq(alice, bob);
    }

    function test_RefusesATemplateWithNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(CheckerFactory.CheckerFactory_TemplateHasNoCode.selector, address(0xDEAD))
        );
        factory.deploy(address(0xDEAD), _cap(200e6));
    }

}
