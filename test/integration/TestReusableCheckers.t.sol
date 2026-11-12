// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { ArgAtMost } from "src/checkers/ArgAtMost.sol";
import { ArgIn } from "src/checkers/ArgIn.sol";
import { CheckerFactory } from "src/checkers/CheckerFactory.sol";
import { CheckerLib } from "src/checkers/CheckerLib.sol";
import { ValueAtMost } from "src/checkers/ValueAtMost.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

/// @notice Reusable checkers running inside the real manager: granted, enforced, shared and combined.
contract TestReusableCheckers is Test, PreparePermission {

    JustaPermissionManager internal manager;
    JustanAccount internal accountImpl;
    ERC20Mock internal token;
    CheckerFactory internal factory;
    ArgIn internal argInTemplate;
    ArgAtMost internal argAtMostTemplate;
    ValueAtMost internal valueAtMostTemplate;

    address internal constant SPENDER = address(0x5E1D);
    address internal constant LANDLORD = address(0x1A4D);
    address internal constant STRANGER = address(0xBAD);
    address internal alice;

    function setUp() public {
        EntryPoint entryPoint = new EntryPoint();
        manager = new JustaPermissionManager();
        accountImpl = new JustanAccount(address(entryPoint), address(0));
        token = new ERC20Mock();
        factory = new CheckerFactory();
        argInTemplate = new ArgIn();
        argAtMostTemplate = new ArgAtMost();
        valueAtMostTemplate = new ValueAtMost();

        alice = TEST_ACCOUNT_ADDRESS;
        _setUpWallet(alice, TEST_ACCOUNT_PRIVATE_KEY);
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    function _setUpWallet(address wallet, uint256 key) internal {
        token.mint(wallet, 1000e6);
        vm.deal(wallet, 1 ether);
        vm.signAndAttachDelegation(address(accountImpl), key);
        vm.prank(wallet);
        JustanAccount(payable(wallet)).addOwnerAddress(address(manager));
    }

    function _onlyTo(address recipient) internal pure returns (bytes memory) {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = bytes32(uint256(uint160(recipient)));
        return abi.encode(TRANSFER_SELECTOR, uint256(0), allowed);
    }

    function _atMost(uint256 max) internal pure returns (bytes memory) {
        return abi.encode(TRANSFER_SELECTOR, uint256(1), max);
    }

    function _permission(
        address wallet,
        address[] memory checkers
    )
        internal
        view
        returns (JustaPermissionManager.Permission memory)
    {
        JustaPermissionManager.CallPermission[] memory calls =
            new JustaPermissionManager.CallPermission[](checkers.length);
        for (uint256 i; i < checkers.length; ++i) {
            calls[i] = createCallWithChecker(address(token), TRANSFER_SELECTOR, checkers[i]);
        }
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(token), 1000e6, JustaPermissionManager.PeriodUnit.Forever, 1);
        return createPermission(
            wallet, SPENDER, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );
    }

    function _one(address a) internal pure returns (address[] memory l) {
        l = new address[](1);
        l[0] = a;
    }

    /// @dev The wallet's single signed batch: deploy each checker, then approve the permission.
    function _grant(
        address wallet,
        address[] memory templates,
        bytes[] memory settings,
        JustaPermissionManager.Permission memory permission
    )
        internal
    {
        BaseAccount.Call[] memory batch = new BaseAccount.Call[](templates.length + 1);
        for (uint256 i; i < templates.length; ++i) {
            batch[i] = BaseAccount.Call({
                target: address(factory),
                value: 0,
                data: abi.encodeCall(CheckerFactory.deploy, (templates[i], settings[i]))
            });
        }
        batch[templates.length] = BaseAccount.Call({
            target: address(manager), value: 0, data: abi.encodeCall(JustaPermissionManager.approve, (permission))
        });
        vm.prank(wallet);
        JustanAccount(payable(wallet)).executeBatch(batch);
    }

    function _grantOne(
        address wallet,
        address template,
        bytes memory settings
    )
        internal
        returns (JustaPermissionManager.Permission memory permission, address checker)
    {
        checker = factory.predict(template, settings);
        permission = _permission(wallet, _one(checker));
        address[] memory templates = new address[](1);
        templates[0] = template;
        bytes[] memory all = new bytes[](1);
        all[0] = settings;
        _grant(wallet, templates, all, permission);
    }

    function _run(JustaPermissionManager.Permission memory permission, bytes memory data) internal {
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(token), value: 0, data: data });
        vm.prank(SPENDER);
        manager.executeBatch(permission, calls);
    }

    /// @dev Approves a permission with a single rule, straight from the wallet.
    function _approveOneRule(
        address target,
        bytes4 selector,
        address checker,
        address spendToken
    )
        internal
        returns (JustaPermissionManager.Permission memory permission)
    {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(target, selector, checker);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(spendToken, 1 ether, JustaPermissionManager.PeriodUnit.Forever, 1);
        permission = createPermission(
            alice, SPENDER, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );
        vm.prank(alice);
        manager.approve(permission);
    }

    function _runCall(
        JustaPermissionManager.Permission memory permission,
        address target,
        uint256 value,
        bytes memory data
    )
        internal
    {
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: target, value: value, data: data });
        vm.prank(SPENDER);
        manager.executeBatch(permission, calls);
    }

    function _expectRejected(address target, bytes4 selector, address checker) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector, target, selector, checker
            )
        );
    }

    function _transfer(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeCall(IERC20.transfer, (to, amount));
    }

    // ------------------------------------------------------------------
    // flows
    // ------------------------------------------------------------------

    function test_OneBatchDeploysTheCheckerAndApprovesThePermission() public {
        address predicted = factory.predict(address(argInTemplate), _onlyTo(LANDLORD));
        assertEq(predicted.code.length, 0, "checker not there before the grant");

        (JustaPermissionManager.Permission memory permission,) =
            _grantOne(alice, address(argInTemplate), _onlyTo(LANDLORD));

        assertGt(predicted.code.length, 0, "grant deployed the checker");
        assertTrue(manager.isApproved(permission));
    }

    function test_SpenderCanPayTheAllowedRecipient() public {
        (JustaPermissionManager.Permission memory permission,) =
            _grantOne(alice, address(argInTemplate), _onlyTo(LANDLORD));

        _run(permission, _transfer(LANDLORD, 100e6));

        assertEq(token.balanceOf(LANDLORD), 100e6);
    }

    function test_SpenderCannotPayAnyoneElse() public {
        (JustaPermissionManager.Permission memory permission, address checker) =
            _grantOne(alice, address(argInTemplate), _onlyTo(LANDLORD));

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(token),
                TRANSFER_SELECTOR,
                checker
            )
        );
        _run(permission, _transfer(STRANGER, 100e6));
    }

    function test_ACheckerForOneFunctionRefusesAnyOtherFunctionUnderAWildcardRule() public {
        address checker = factory.deploy(address(argInTemplate), _onlyTo(LANDLORD));

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](1);
        calls[0] = createCallWithChecker(address(token), manager.ANY_FN_SEL(), checker);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(address(token), 1000e6, JustaPermissionManager.PeriodUnit.Forever, 1);
        JustaPermissionManager.Permission memory permission = createPermission(
            alice, SPENDER, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );
        vm.prank(alice);
        manager.approve(permission);

        // approve(LANDLORD, ...) has the landlord in slot 0, but it is not transfer.
        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(token),
                IERC20.approve.selector,
                checker
            )
        );
        _run(permission, abi.encodeCall(IERC20.approve, (LANDLORD, 100e6)));
    }

    function test_AccountRuleLetsTheWalletPayOnlyItself() public {
        (JustaPermissionManager.Permission memory permission, address checker) =
            _grantOne(alice, address(argInTemplate), _onlyTo(CheckerLib.ACCOUNT));

        _run(permission, _transfer(alice, 1e6));
        assertEq(token.balanceOf(alice), 1000e6, "paid itself, balance unchanged");

        _expectRejected(address(token), TRANSFER_SELECTOR, checker);
        _run(permission, _transfer(STRANGER, 1e6));
    }

    function test_ASecondWalletReusesTheSameCheckerWithoutANewDeploy() public {
        (, address aliceChecker) = _grantOne(alice, address(argInTemplate), _onlyTo(CheckerLib.ACCOUNT));

        (address bob, uint256 bobKey) = makeAddrAndKey("bob");
        _setUpWallet(bob, bobKey);

        vm.recordLogs();
        (JustaPermissionManager.Permission memory bobPermission, address bobChecker) =
            _grantOne(bob, address(argInTemplate), _onlyTo(CheckerLib.ACCOUNT));

        assertEq(bobChecker, aliceChecker, "same rule, same checker");
        bytes32 deployed = keccak256("CheckerDeployed(address,address,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics.length == 0 || logs[i].topics[0] != deployed, "no second deploy");
        }

        // The shared checker still means "this wallet" for bob.
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call({ target: address(token), value: 0, data: _transfer(alice, 1e6) });
        _expectRejected(address(token), TRANSFER_SELECTOR, bobChecker);
        vm.prank(SPENDER);
        manager.executeBatch(bobPermission, calls);
    }

    function test_TwoRulesOnTheSameFunctionMustBothPass() public {
        address onlyLandlord = factory.predict(address(argInTemplate), _onlyTo(LANDLORD));
        address upTo200 = factory.predict(address(argAtMostTemplate), _atMost(200e6));

        address[] memory checkers = new address[](2);
        checkers[0] = onlyLandlord;
        checkers[1] = upTo200;
        JustaPermissionManager.Permission memory permission = _permission(alice, checkers);

        address[] memory templates = new address[](2);
        templates[0] = address(argInTemplate);
        templates[1] = address(argAtMostTemplate);
        bytes[] memory settings = new bytes[](2);
        settings[0] = _onlyTo(LANDLORD);
        settings[1] = _atMost(200e6);
        _grant(alice, templates, settings, permission);

        _run(permission, _transfer(LANDLORD, 200e6));
        assertEq(token.balanceOf(LANDLORD), 200e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(token),
                TRANSFER_SELECTOR,
                upTo200
            )
        );
        _run(permission, _transfer(LANDLORD, 200e6 + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector,
                address(token),
                TRANSFER_SELECTOR,
                onlyLandlord
            )
        );
        _run(permission, _transfer(STRANGER, 1e6));
    }

    function test_ValueCapLimitsAPlainEthSend() public {
        bytes4 emptySel = manager.EMPTY_CALLDATA_FN_SEL();
        address checker = factory.deploy(address(valueAtMostTemplate), abi.encode(emptySel, uint256(0.1 ether)));
        JustaPermissionManager.Permission memory permission =
            _approveOneRule(LANDLORD, emptySel, checker, manager.NATIVE_TOKEN());

        _runCall(permission, LANDLORD, 0.1 ether, "");
        assertEq(LANDLORD.balance, 0.1 ether);

        _expectRejected(LANDLORD, emptySel, checker);
        _runCall(permission, LANDLORD, 0.1 ether + 1, "");
    }

    function test_ValueCapRefusesAFunctionCallUnderAWildcardRule() public {
        bytes4 emptySel = manager.EMPTY_CALLDATA_FN_SEL();
        address checker = factory.deploy(address(valueAtMostTemplate), abi.encode(emptySel, uint256(0.1 ether)));
        JustaPermissionManager.Permission memory permission =
            _approveOneRule(LANDLORD, manager.ANY_FN_SEL(), checker, manager.NATIVE_TOKEN());

        bytes4 depositSel = 0xd0e30db0; // deposit()
        bytes memory deposit = abi.encodeWithSelector(depositSel);
        _expectRejected(LANDLORD, depositSel, checker);
        _runCall(permission, LANDLORD, 0.01 ether, deposit);
    }

    function test_AmountCapRefusesAnotherFunctionUnderAWildcardRule() public {
        address checker = factory.deploy(address(argAtMostTemplate), _atMost(200e6));
        JustaPermissionManager.Permission memory permission =
            _approveOneRule(address(token), manager.ANY_FN_SEL(), checker, address(token));

        // approve has a small number in slot 1 too, but it is not transfer.
        _expectRejected(address(token), IERC20.approve.selector, checker);
        _runCall(permission, address(token), 0, abi.encodeCall(IERC20.approve, (LANDLORD, 1)));
    }

    function test_DeployAndCheckStayWithinGasBudget() public {
        uint256 before = gasleft();
        address checker = factory.deploy(address(argInTemplate), _onlyTo(LANDLORD));
        uint256 deployGas = before - gasleft();

        before = gasleft();
        factory.deploy(address(argInTemplate), _onlyTo(LANDLORD));
        uint256 redeployGas = before - gasleft();

        bytes memory data = _transfer(LANDLORD, 1);
        before = gasleft();
        ArgIn(checker).canExecute(0, alice, SPENDER, address(token), 0, data);
        uint256 checkGas = before - gasleft();

        // Measured about 91k, 3k and 7.3k. The budgets catch a regression, not the exact number.
        assertLt(deployGas, 120_000, "first deploy of a rule");
        assertLt(redeployGas, 10_000, "deploy of a rule that already exists");
        assertLt(checkGas, 15_000, "one cold check");
    }

}
