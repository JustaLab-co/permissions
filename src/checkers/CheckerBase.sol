// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { LibClone } from "solady/utils/LibClone.sol";
import { ICallChecker } from "src/interfaces/ICallChecker.sol";

/**
 * @title CheckerBase
 * @notice Shared plumbing for checker templates. A template is never used directly: each use case is a
 *         clone made by CheckerFactory with its settings appended to the clone's code.
 */
abstract contract CheckerBase is ICallChecker {

    /// @dev The template's own address. A call that runs at this address is not a clone.
    address private immutable _TEMPLATE = address(this);

    /// @inheritdoc ICallChecker
    function canExecute(
        bytes32,
        address account,
        address,
        address,
        uint256 value,
        bytes calldata data
    )
        external
        view
        returns (bool)
    {
        // The template has no settings, so it refuses everything.
        if (address(this) == _TEMPLATE) {
            return false;
        }
        return _check(LibClone.argsOnClone(address(this)), account, value, data);
    }

    /// @dev Decides the call from the clone's settings.
    function _check(
        bytes memory settings,
        address account,
        uint256 value,
        bytes calldata data
    )
        internal
        pure
        virtual
        returns (bool);

}
