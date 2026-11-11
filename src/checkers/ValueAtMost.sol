// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { CheckerBase } from "./CheckerBase.sol";
import { CheckerLib } from "./CheckerLib.sol";

/**
 * @title ValueAtMost
 * @notice Passes when the call is to `selector` and sends at most `max` of the native token.
 * @dev Settings: abi.encode(bytes4 selector, uint256 max). Use 0xe0e0e0e0 as the selector for a
 *      plain send with no calldata, matching the manager.
 */
contract ValueAtMost is CheckerBase {

    function _check(
        bytes memory settings,
        address,
        uint256 value,
        bytes calldata data
    )
        internal
        pure
        override
        returns (bool)
    {
        (bytes4 selector, uint256 max) = abi.decode(settings, (bytes4, uint256));
        return CheckerLib.selectorOf(data) == selector && value <= max;
    }

}
