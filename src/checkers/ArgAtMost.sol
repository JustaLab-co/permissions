// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { CheckerBase } from "./CheckerBase.sol";
import { CheckerLib } from "./CheckerLib.sol";

/**
 * @title ArgAtMost
 * @notice Passes when the call is to `selector` and its argument at `slot`, read as an unsigned
 *         number, is at most `max`.
 * @dev Settings: abi.encode(bytes4 selector, uint256 slot, uint256 max). Per call only: totals over
 *      time belong to the manager's spend limits.
 */
contract ArgAtMost is CheckerBase {

    function _check(bytes memory settings, address, uint256, bytes calldata data)
        internal
        pure
        override
        returns (bool)
    {
        (bytes4 selector, uint256 slot, uint256 max) = abi.decode(settings, (bytes4, uint256, uint256));
        if (CheckerLib.selectorOf(data) != selector) {
            return false;
        }

        (bool found, bytes32 word) = CheckerLib.wordAt(data, slot);
        return found && uint256(word) <= max;
    }

}
