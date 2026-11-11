// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { CheckerBase } from "./CheckerBase.sol";
import { CheckerLib } from "./CheckerLib.sol";

/**
 * @title ArgIn
 * @notice Passes when the call is to `selector` and its argument at `slot` is one of `allowed`.
 * @dev Settings: abi.encode(bytes4 selector, uint256 slot, bytes32[] allowed).
 *      An address is stored left padded, as ABI encoding has it. CheckerLib.ACCOUNT in the list
 *      stands for the account running the call.
 */
contract ArgIn is CheckerBase {

    function _check(
        bytes memory settings,
        address account,
        uint256,
        bytes calldata data
    )
        internal
        pure
        override
        returns (bool)
    {
        (bytes4 selector, uint256 slot, bytes32[] memory allowed) = abi.decode(settings, (bytes4, uint256, bytes32[]));
        if (CheckerLib.selectorOf(data) != selector) {
            return false;
        }

        (bool found, bytes32 word) = CheckerLib.wordAt(data, slot);
        if (!found) {
            return false;
        }

        bytes32 sentinel = bytes32(uint256(uint160(CheckerLib.ACCOUNT)));
        bytes32 self = bytes32(uint256(uint160(account)));
        for (uint256 i; i < allowed.length; ++i) {
            bytes32 value = allowed[i] == sentinel ? self : allowed[i];
            if (word == value) {
                return true;
            }
        }
        return false;
    }

}
