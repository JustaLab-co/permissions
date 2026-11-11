// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console2 } from "forge-std/Script.sol";
import { JustanAccount } from "justanaccount/JustanAccount.sol";

import { JustaPermissionManager } from "../src/JustaPermissionManager.sol";
import { CheckerFactory } from "../src/checkers/CheckerFactory.sol";
import { CheckerLib } from "../src/checkers/CheckerLib.sol";
import { ERC20Mock } from "../test/mocks/ERC20Mock.sol";
import { BaseSepoliaCheckerRun, ISwapRouter02, IWETH } from "./BaseSepoliaCheckerRun.sol";

/**
 * @notice A live run of the reusable checkers on Base Sepolia, from a test wallet owned by an EOA.
 *         The owner signs one grant batch; the spender then pays the landlord and swaps for the wallet.
 *         Last, it simulates the calls that must be refused against the resulting state and fails the
 *         run unless each is refused by the checker meant to refuse it.
 * @dev Env: OWNER_PK, SPENDER_PK. Test only: the wallet's owner is a plain key, not a passkey.
 */
contract LiveCheckerRun is BaseSepoliaCheckerRun {

    CheckerFactory internal constant FACTORY = CheckerFactory(0x48C9554e534c84eF5B4dcc1E85371785477DBC1E);
    address internal constant ARG_IN = 0x40F24cbdd8C23699647001d043D005B9b2114479;
    address internal constant ARG_AT_MOST = 0x70f37b4DBE07b6494Be359b937955bF59f0C330B;
    address internal constant LANDLORD = address(0x1A4D);
    address internal constant STRANGER = address(0xBAD);
    uint256 internal constant SWAP_IN = 0.0005 ether;

    struct Checkers {
        address onlyLandlord;
        address upTo100;
        address swapPaysWallet;
        address approveRouter;
    }

    JustanAccount internal wallet;
    ERC20Mock internal token;
    address internal spender;

    function run() public {
        uint256 ownerPk = vm.envUint("OWNER_PK");
        uint256 spenderPk = vm.envUint("SPENDER_PK");
        address owner = vm.addr(ownerPk);
        spender = vm.addr(spenderPk);

        // 1. Set up: the test wallet, some ETH in it, and a test token.
        vm.startBroadcast(ownerPk);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(owner);
        wallet = JustanAccount(payable(ACCOUNT_FACTORY.getAddress(owners, 0)));
        if (address(wallet).code.length == 0) {
            ACCOUNT_FACTORY.createAccount(owners, 0);
        }
        if (address(wallet).balance < 0.002 ether) {
            (bool sent,) = address(wallet).call{ value: 0.002 ether }("");
            require(sent, "funding the wallet failed");
        }
        token = new ERC20Mock();
        token.mint(address(wallet), 1000e18);
        vm.stopBroadcast();

        // 2. The rules, each a shared checker at an address known before it exists.
        bytes memory onlyLandlord = _argIn(IERC20.transfer.selector, 0, LANDLORD);
        bytes memory upTo100 = abi.encode(IERC20.transfer.selector, uint256(1), uint256(100e18));
        bytes memory swapPaysWallet = _argIn(ISwapRouter02.exactInputSingle.selector, 3, CheckerLib.ACCOUNT);
        bytes memory approveRouter = _argIn(IERC20.approve.selector, 0, address(ROUTER));
        Checkers memory checkers = Checkers({
            onlyLandlord: FACTORY.predict(ARG_IN, onlyLandlord),
            upTo100: FACTORY.predict(ARG_AT_MOST, upTo100),
            swapPaysWallet: FACTORY.predict(ARG_IN, swapPaysWallet),
            approveRouter: FACTORY.predict(ARG_IN, approveRouter)
        });
        JustaPermissionManager.Permission memory permission = _permission(checkers);

        // 3. The owner's one signed grant batch.
        // Adding the manager as an owner is skipped on a rerun, where it already is one.
        bool addManager = !wallet.isOwnerAddress(address(MANAGER));
        BaseAccount.Call[] memory grant = new BaseAccount.Call[](addManager ? 7 : 6);
        uint256 n;
        grant[n++] = _call(WETH, 0.001 ether, abi.encodeCall(IWETH.deposit, ()));
        if (addManager) {
            grant[n++] = _call(address(wallet), 0, abi.encodeCall(wallet.addOwnerAddress, (address(MANAGER))));
        }
        grant[n++] = _call(address(FACTORY), 0, abi.encodeCall(CheckerFactory.deploy, (ARG_IN, onlyLandlord)));
        grant[n++] = _call(address(FACTORY), 0, abi.encodeCall(CheckerFactory.deploy, (ARG_AT_MOST, upTo100)));
        grant[n++] = _call(address(FACTORY), 0, abi.encodeCall(CheckerFactory.deploy, (ARG_IN, swapPaysWallet)));
        grant[n++] = _call(address(FACTORY), 0, abi.encodeCall(CheckerFactory.deploy, (ARG_IN, approveRouter)));
        grant[n++] = _call(address(MANAGER), 0, abi.encodeCall(JustaPermissionManager.approve, (permission)));
        vm.broadcast(ownerPk);
        wallet.executeBatch(grant);

        // 4. The spender runs allowed calls under the permission.
        vm.startBroadcast(spenderPk);
        MANAGER.executeBatch(
            permission, _singleCall(address(token), abi.encodeCall(IERC20.transfer, (LANDLORD, 50e18)))
        );
        MANAGER.executeBatch(permission, _swapCalls(address(ROUTER), address(wallet), SWAP_IN));
        vm.stopBroadcast();

        console2.log("wallet", address(wallet));
        console2.log("token", address(token));

        // 5. Calls that must be refused, simulated as the spender; never broadcast.
        _assertRefused(
            "pay a stranger",
            permission,
            _singleCall(address(token), abi.encodeCall(IERC20.transfer, (STRANGER, 1e18))),
            _rejection(address(token), IERC20.transfer.selector, checkers.onlyLandlord)
        );
        _assertRefused(
            "pay the landlord over 100",
            permission,
            _singleCall(address(token), abi.encodeCall(IERC20.transfer, (LANDLORD, 101e18))),
            _rejection(address(token), IERC20.transfer.selector, checkers.upTo100)
        );
        _assertRefused(
            "swap paying a stranger",
            permission,
            _swapCalls(address(ROUTER), STRANGER, SWAP_IN),
            _rejection(address(ROUTER), ISwapRouter02.exactInputSingle.selector, checkers.swapPaysWallet)
        );
        _assertRefused(
            "approve a stranger",
            permission,
            _swapCalls(STRANGER, address(wallet), SWAP_IN),
            _rejection(WETH, IERC20.approve.selector, checkers.approveRouter)
        );
    }

    function _permission(Checkers memory checkers) internal view returns (JustaPermissionManager.Permission memory) {
        JustaPermissionManager.CallPermission[] memory calls = new JustaPermissionManager.CallPermission[](4);
        calls[0] = createCallWithChecker(address(token), IERC20.transfer.selector, checkers.onlyLandlord);
        calls[1] = createCallWithChecker(address(token), IERC20.transfer.selector, checkers.upTo100);
        calls[2] =
            createCallWithChecker(address(ROUTER), ISwapRouter02.exactInputSingle.selector, checkers.swapPaysWallet);
        calls[3] = createCallWithChecker(WETH, IERC20.approve.selector, checkers.approveRouter);

        JustaPermissionManager.SpendLimit[] memory spends = new JustaPermissionManager.SpendLimit[](2);
        spends[0] = createSpendLimit(address(token), 500e18, JustaPermissionManager.PeriodUnit.Day, 1);
        spends[1] = createSpendLimit(WETH, 0.001 ether, JustaPermissionManager.PeriodUnit.Day, 1);

        // A fresh token each run gives a fresh salt, so each run is its own permission.
        return createPermission(
            address(wallet),
            spender,
            uint48(block.timestamp),
            uint48(block.timestamp + 1 days),
            uint256(uint160(address(token))),
            calls,
            spends
        );
    }

    function _assertRefused(
        string memory label,
        JustaPermissionManager.Permission memory permission,
        BaseAccount.Call[] memory calls,
        bytes memory expected
    )
        internal
    {
        vm.prank(spender);
        try MANAGER.executeBatch(permission, calls) {
            revert(string.concat("not refused: ", label));
        } catch (bytes memory reason) {
            require(keccak256(reason) == keccak256(expected), string.concat("refused for the wrong reason: ", label));
        }
        console2.log(string.concat("refused as expected: ", label));
    }

}
