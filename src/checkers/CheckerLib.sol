// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title CheckerLib
 * @notice Shared helpers for the reusable call checkers.
 */
library CheckerLib {

    /// @notice Stands for "the account running this call" inside a checker's settings.
    /// @dev Lets one shared checker mean "pay me" for every account.
    address internal constant ACCOUNT = 0xAcc0Acc0acC0ACc0Acc0AcC0ACc0ACc0acc0Acc0;

    /// @notice The selector the manager uses for calldata shorter than 4 bytes.
    bytes4 internal constant EMPTY_CALLDATA_FN_SEL = 0xe0e0e0e0;

    /// @notice Returns the call's selector, matching how the manager reads it.
    function selectorOf(bytes calldata data) internal pure returns (bytes4) {
        return data.length >= 4 ? bytes4(data[:4]) : EMPTY_CALLDATA_FN_SEL;
    }

    /// @notice Reads the 32 byte argument word at `slot`, counted after the selector.
    /// @return found False when the calldata is too short to hold that whole word.
    function wordAt(bytes calldata data, uint256 slot) internal pure returns (bool found, bytes32 word) {
        // Bounding `slot` first keeps the offset math from overflowing.
        if (data.length < 36 || slot > (data.length - 36) / 32) {
            return (false, bytes32(0));
        }
        uint256 offset = 4 + slot * 32;
        return (true, bytes32(data[offset:offset + 32]));
    }

}
