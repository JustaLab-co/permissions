// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";
import { JustanAccountFactory } from "justanaccount/JustanAccountFactory.sol";
import { PreparePermission } from "script/PreparePermission.s.sol";
import { JustaPermissionManager } from "src/JustaPermissionManager.sol";
import { ArgIn } from "src/checkers/ArgIn.sol";
import { CheckerFactory } from "src/checkers/CheckerFactory.sol";
import { CheckerLib } from "src/checkers/CheckerLib.sol";

interface ISwapRouter02 {

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

}

interface IWETH {

    function deposit() external payable;

}

/// @notice The ENGR-1422 case on a Base Sepolia fork: an agent may swap for the wallet through the real
///         Uniswap router and the real deployed manager, but the swap can only pay the wallet itself.
/// @dev Skips unless BASE_SEPOLIA_RPC_URL is set.
contract TestReusableCheckersFork is Test, PreparePermission {

    JustaPermissionManager internal constant MANAGER =
        JustaPermissionManager(0xf1b40E3D5701C04d86F7828f0EB367B9C90901D8);
    JustanAccountFactory internal constant ACCOUNT_FACTORY =
        JustanAccountFactory(0x5803c076563C85799989d42Fc00292A8aE52fa9E);
    ISwapRouter02 internal constant ROUTER = ISwapRouter02(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4);
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    uint24 internal constant POOL_FEE = 3000;

    /// @dev Settings for an ArgIn checker that allows a single value.
    function _argIn(bytes4 selector, uint256 slot, address value) internal pure returns (bytes memory) {
        bytes32[] memory allowed = new bytes32[](1);
        allowed[0] = bytes32(uint256(uint160(value)));
        return abi.encode(selector, slot, allowed);
    }

    function _call(address target, uint256 value, bytes memory data) internal pure returns (BaseAccount.Call memory) {
        return BaseAccount.Call({ target: target, value: value, data: data });
    }

    /// @dev The spender's swap: approve WETH to `approveTo`, then swap WETH for USDC paying `recipient`.
    function _swapCalls(
        address approveTo,
        address recipient,
        uint256 amountIn
    )
        internal
        pure
        returns (BaseAccount.Call[] memory calls)
    {
        calls = new BaseAccount.Call[](2);
        calls[0] = _call(WETH, 0, abi.encodeCall(IERC20.approve, (approveTo, amountIn)));
        calls[1] = _call(
            address(ROUTER),
            0,
            abi.encodeCall(
                ISwapRouter02.exactInputSingle,
                (ISwapRouter02.ExactInputSingleParams({
                        tokenIn: WETH,
                        tokenOut: USDC,
                        fee: POOL_FEE,
                        recipient: recipient,
                        amountIn: amountIn,
                        amountOutMinimum: 1,
                        sqrtPriceLimitX96: 0
                    }))
            )
        );
    }

    function _rejection(address target, bytes4 selector, address checker) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            JustaPermissionManager.JustaPermissionManager_CheckerRejectedCall.selector, target, selector, checker
        );
    }

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
