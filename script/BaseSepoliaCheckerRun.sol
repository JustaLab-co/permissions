// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { JustanAccountFactory } from "justanaccount/JustanAccountFactory.sol";

import { JustaPermissionManager } from "../src/JustaPermissionManager.sol";
import { PreparePermission } from "./PreparePermission.s.sol";

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

/**
 * @notice Base Sepolia addresses and call builders shared by the checker fork test and the live run.
 */
abstract contract BaseSepoliaCheckerRun is PreparePermission {

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

    function _singleCall(address target, bytes memory data) internal pure returns (BaseAccount.Call[] memory calls) {
        calls = new BaseAccount.Call[](1);
        calls[0] = _call(target, 0, data);
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

}
