// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { LibClone } from "solady/utils/LibClone.sol";

/**
 * @title CheckerFactory
 * @notice Makes small clones of checker templates with their settings baked into the clone's code.
 * @dev Open to anyone, with no owner and no upgrades. A clone's address depends only on the template
 *      and the settings, so the same rule always lands at the same address and is deployed once,
 *      then shared. Which templates to trust is decided off chain by whoever shows the rule to the user.
 */
contract CheckerFactory {

    /// @notice A new checker was deployed.
    event CheckerDeployed(address indexed template, address indexed checker, bytes settings);

    /// @notice The template address has no code, so a clone of it could never pass a call.
    error CheckerFactory_TemplateHasNoCode(address template);

    /// @notice Returns the checker for `template` with `settings`, deploying it if it isn't there yet.
    /// @dev Never reverts for an already deployed checker, so a grant batch can always include it.
    function deploy(address template, bytes calldata settings) external returns (address checker) {
        if (template.code.length == 0) {
            revert CheckerFactory_TemplateHasNoCode(template);
        }

        bool alreadyDeployed;
        (alreadyDeployed, checker) = LibClone.createDeterministicClone(template, settings, bytes32(0));
        if (!alreadyDeployed) {
            emit CheckerDeployed(template, checker, settings);
        }
    }

    /// @notice Returns where the checker for `template` with `settings` lives, deployed or not.
    function predict(address template, bytes calldata settings) external view returns (address) {
        return LibClone.predictDeterministicAddress(template, settings, bytes32(0), address(this));
    }

}
