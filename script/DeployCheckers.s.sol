// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { SafeSingletonDeployer } from "safe-singleton-deployer-sol/src/SafeSingletonDeployer.sol";

import { ArgAtMost } from "../src/checkers/ArgAtMost.sol";
import { ArgIn } from "../src/checkers/ArgIn.sol";
import { CheckerFactory } from "../src/checkers/CheckerFactory.sol";
import { ValueAtMost } from "../src/checkers/ValueAtMost.sol";

/**
 * @notice Deploys the checker factory and the checker templates through the Safe singleton deployer,
 *         so the same code lands at the same address on every chain. Anything already there is skipped.
 */
contract DeployCheckers is Script {

    bytes32 internal constant SALT = bytes32(uint256(1));
    address internal constant SAFE_SINGLETON_FACTORY = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    function run() public returns (address factory, address argIn, address argAtMost, address valueAtMost) {
        console2.log("Deploying checkers on chain ID", block.chainid);
        factory = _deploy("CheckerFactory", type(CheckerFactory).creationCode);
        argIn = _deploy("ArgIn", type(ArgIn).creationCode);
        argAtMost = _deploy("ArgAtMost", type(ArgAtMost).creationCode);
        valueAtMost = _deploy("ValueAtMost", type(ValueAtMost).creationCode);
    }

    function _deploy(string memory name, bytes memory creationCode) internal returns (address deployed) {
        // Computed here rather than with the library's public computeAddress, which would make forge
        // deploy the library itself first.
        deployed = vm.computeCreate2Address(SALT, keccak256(creationCode), SAFE_SINGLETON_FACTORY);
        if (deployed.code.length > 0) {
            console2.log(string.concat(name, " already deployed at"), deployed);
            return deployed;
        }
        address actual = SafeSingletonDeployer.broadcastDeploy(creationCode, SALT);
        require(actual == deployed, "unexpected address");
        console2.log(string.concat(name, " deployed at"), deployed);
    }

}
