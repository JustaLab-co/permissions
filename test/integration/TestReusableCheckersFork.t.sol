// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { BaseSepoliaCheckerRun, ISwapRouter02, IWETH } from "script/BaseSepoliaCheckerRun.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { ArgIn } from "src/checkers/ArgIn.sol";
import { CheckerFactory } from "src/checkers/CheckerFactory.sol";
import { CheckerLib } from "src/checkers/CheckerLib.sol";

/// @notice The ENGR-1422 case on a Base Sepolia fork: an agent may swap for the wallet through the real
///         Uniswap router and the real deployed manager, but the swap can only pay the wallet itself.
/// @dev Skips unless BASE_SEPOLIA_RPC_URL is set.
contract TestReusableCheckersFork is Test, BaseSepoliaCheckerRun {

    uint256 internal constant FORK_BLOCK = 57_355_600;
    uint256 internal constant SWAP_IN = 0.001 ether;

    address internal owner = makeAddr("owner");
    address internal spender = makeAddr("agent");
    address internal stranger = makeAddr("stranger");

    JustanAccount internal wallet;
    CheckerFactory internal factory;
    ArgIn internal argIn;
    JustaPermissionManager.Permission internal permission;
    address internal swapChecker;
    address internal approveChecker;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpc, FORK_BLOCK);

        factory = new CheckerFactory();
        argIn = new ArgIn();

        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        wallet = ACCOUNT_FACTORY.createAccount(owners, uint256(keccak256("checker-fork")));
        vm.deal(address(wallet), 1 ether);

        // Swap: recipient (slot 3 of exactInputSingle) must be the wallet itself.
        bytes memory swapRule = _argIn(ISwapRouter02.exactInputSingle.selector, 3, CheckerLib.ACCOUNT);
        // Approve on WETH: the spender (slot 0) must be the router.
        bytes memory approveRule = _argIn(IERC20.approve.selector, 0, address(ROUTER));
        swapChecker = factory.predict(address(argIn), swapRule);
        approveChecker = factory.predict(address(argIn), approveRule);

        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](2);
        calls[0] = createCallWithChecker(address(ROUTER), ISwapRouter02.exactInputSingle.selector, swapChecker);
        calls[1] = createCallWithChecker(WETH, IERC20.approve.selector, approveChecker);
        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](1);
        spends[0] = createSpendLimit(WETH, 0.01 ether, JustaPermissionManager.PeriodUnit.Day, 1);
        permission = createPermission(
            address(wallet), spender, uint48(block.timestamp), uint48(block.timestamp + 1 days), 0, calls, spends
        );

        // The owner's one signed batch: wrap ETH, let the manager act, deploy both checkers, approve.
        BaseAccount.Call[] memory grant = new BaseAccount.Call[](5);
        grant[0] = _call(WETH, 0.01 ether, abi.encodeCall(IWETH.deposit, ()));
        grant[1] = _call(address(wallet), 0, abi.encodeCall(wallet.addOwnerAddress, (address(MANAGER))));
        grant[2] = _call(address(factory), 0, abi.encodeCall(CheckerFactory.deploy, (address(argIn), swapRule)));
        grant[3] = _call(address(factory), 0, abi.encodeCall(CheckerFactory.deploy, (address(argIn), approveRule)));
        grant[4] = _call(address(MANAGER), 0, abi.encodeCall(JustaPermissionManager.approve, (permission)));
        vm.prank(owner);
        wallet.executeBatch(grant);
    }

    function test_GrantDeployedBothCheckersAndApproved() public view {
        assertGt(swapChecker.code.length, 0);
        assertGt(approveChecker.code.length, 0);
        assertTrue(MANAGER.isApproved(permission));
    }

    function test_AgentSwapThatPaysTheWalletGoesThrough() public {
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(wallet));

        vm.prank(spender);
        MANAGER.executeBatch(permission, _swapCalls(address(ROUTER), address(wallet), SWAP_IN));

        assertGt(IERC20(USDC).balanceOf(address(wallet)), usdcBefore, "wallet received USDC");
        assertEq(IERC20(WETH).allowance(address(wallet), address(ROUTER)), 0, "manager cleaned up the approval");
    }

    function test_AgentSwapThatPaysAnyoneElseIsRefused() public {
        vm.expectRevert(_rejection(address(ROUTER), ISwapRouter02.exactInputSingle.selector, swapChecker));
        vm.prank(spender);
        MANAGER.executeBatch(permission, _swapCalls(address(ROUTER), stranger, SWAP_IN));
    }

    function test_AgentCannotApproveAnyoneButTheRouter() public {
        vm.expectRevert(_rejection(WETH, IERC20.approve.selector, approveChecker));
        vm.prank(spender);
        MANAGER.executeBatch(permission, _swapCalls(stranger, address(wallet), SWAP_IN));
    }

}
