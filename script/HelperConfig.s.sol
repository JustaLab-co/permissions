// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { Script, console2 } from "forge-std/Script.sol";

abstract contract CodeConstants {

    ////////////////////////////////////////////////////////////////////////
    // CHAIN IDS
    ////////////////////////////////////////////////////////////////////////

    uint256 public constant LOCAL_CHAIN_ID = 31_337;

    uint256 public constant MAINNET_ETH_CHAIN_ID = 1;
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11_155_111;

    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84_532;

    uint256 public constant OPTIMISM_CHAIN_ID = 10;
    uint256 public constant OPTIMISM_SEPOLIA_CHAIN_ID = 11_155_420;

    uint256 public constant ARBITRUM_ONE_CHAIN_ID = 42_161;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421_614;

    uint256 public constant AVALANCHE_CHAIN_ID = 43_114;
    uint256 public constant AVALANCHE_FUJI_CHAIN_ID = 43_113;

    uint256 public constant BSC_CHAIN_ID = 56;
    uint256 public constant BSC_TESTNET_CHAIN_ID = 97;

    uint256 public constant LINEA_CHAIN_ID = 59_144;
    uint256 public constant LINEA_SEPOLIA_CHAIN_ID = 59_141;

    uint256 public constant CELO_CHAIN_ID = 42_220;
    uint256 public constant CELO_SEPOLIA_CHAIN_ID = 11_142_220;

    uint256 public constant FLARE_CHAIN_ID = 14;
    uint256 public constant FLARE_COSTON2_CHAIN_ID = 114;

    uint256 public constant INK_CHAIN_ID = 57_073;
    uint256 public constant INK_SEPOLIA_CHAIN_ID = 763_373;

    uint256 public constant DOS_CHAIN_ID = 7979;

    uint256 public constant GNOSIS_CHAIN_ID = 100;

    uint256 public constant ARC_TESTNET_CHAIN_ID = 5_042_002;

    uint256 public constant POLYGON_CHAIN_ID = 137;
    uint256 public constant POLYGON_AMOY_CHAIN_ID = 80_002;

    uint256 public constant ROBINHOOD_CHAIN_ID = 4663;

    uint256 public constant SONEIUM_CHAIN_ID = 1868;

    uint256 public constant HYVECHAIN_CHAIN_ID = 7847;

    uint256 public constant UNICHAIN_CHAIN_ID = 130;

    uint256 public constant MONAD_CHAIN_ID = 143;

    ////////////////////////////////////////////////////////////////////////
    // ENTRY POINT
    ////////////////////////////////////////////////////////////////////////

    /// @notice Address of the v0.8 EntryPoint contract.
    address public constant ENTRYPOINT_ADDRESS = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    ////////////////////////////////////////////////////////////////////////
    // TEST ACCOUNTS (Anvil defaults)
    ////////////////////////////////////////////////////////////////////////

    // Anvil default account #1
    address payable public constant TEST_ACCOUNT_ADDRESS = payable(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
    uint256 public constant TEST_ACCOUNT_PRIVATE_KEY =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    // Secp256k1 curve order for signature validation
    uint256 public constant SECP256K1_CURVE_ORDER =
        115_792_089_237_316_195_423_570_985_008_687_907_852_837_564_279_074_904_382_605_163_141_518_161_494_337;

    ////////////////////////////////////////////////////////////////////////
    // JUSTA PERMISSION MANAGER CONSTANTS (mirrored from contract)
    ////////////////////////////////////////////////////////////////////////

    /// @notice ERC-7528 native token address convention.
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Canonical Permit2 contract address.
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Wildcard for any target address.
    address public constant ANY_TARGET = 0x3232323232323232323232323232323232323232;

    /// @notice Wildcard for any function selector.
    bytes4 public constant ANY_FN_SEL = 0x32323232;

    /// @notice Selector for empty calldata.
    bytes4 public constant EMPTY_CALLDATA_FN_SEL = 0xe0e0e0e0;

    ////////////////////////////////////////////////////////////////////////
    // EIP-712 TYPEHASHES (mirrored from contract)
    ////////////////////////////////////////////////////////////////////////

    bytes32 public constant CALL_PERMISSION_TYPEHASH =
        keccak256("CallPermission(address target,bytes4 selector,address checker)");

    bytes32 public constant SPEND_LIMIT_TYPEHASH =
        keccak256("SpendLimit(address token,uint160 allowance,uint8 unit,uint16 multiplier)");

    bytes32 public constant PERMISSION_TYPEHASH = keccak256(
        "Permission(address account,address spender,uint48 start,uint48 end,uint256 salt,CallPermission[] calls,SpendLimit[] spends)CallPermission(address target,bytes4 selector,address checker)SpendLimit(address token,uint160 allowance,uint8 unit,uint16 multiplier)"
    );

    ////////////////////////////////////////////////////////////////////////
    // COMMON FUNCTION SELECTORS
    ////////////////////////////////////////////////////////////////////////

    bytes4 public constant TRANSFER_SELECTOR = 0xa9059cbb; // transfer(address,uint256)
    bytes4 public constant TRANSFER_FROM_SELECTOR = 0x23b872dd; // transferFrom(address,address,uint256)
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3; // approve(address,uint256)
    bytes4 public constant PERMIT2_APPROVE_SELECTOR = 0x87517c45; // approve(address,address,uint160,uint48)
    bytes4 public constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351; // increaseAllowance(address,uint256)

}

contract HelperConfig is CodeConstants, Script {

    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address entryPointAddress;
    }

    function isSupportedChain(uint256 chainId) public pure returns (bool) {
        return chainId == ETH_SEPOLIA_CHAIN_ID || chainId == MAINNET_ETH_CHAIN_ID || chainId == BASE_CHAIN_ID
            || chainId == BASE_SEPOLIA_CHAIN_ID || chainId == OPTIMISM_CHAIN_ID || chainId == OPTIMISM_SEPOLIA_CHAIN_ID
            || chainId == ARBITRUM_ONE_CHAIN_ID || chainId == ARBITRUM_SEPOLIA_CHAIN_ID || chainId == AVALANCHE_CHAIN_ID
            || chainId == AVALANCHE_FUJI_CHAIN_ID || chainId == BSC_CHAIN_ID || chainId == BSC_TESTNET_CHAIN_ID
            || chainId == LINEA_CHAIN_ID || chainId == LINEA_SEPOLIA_CHAIN_ID || chainId == CELO_CHAIN_ID
            || chainId == CELO_SEPOLIA_CHAIN_ID || chainId == FLARE_CHAIN_ID || chainId == FLARE_COSTON2_CHAIN_ID
            || chainId == INK_CHAIN_ID || chainId == INK_SEPOLIA_CHAIN_ID || chainId == DOS_CHAIN_ID
            || chainId == GNOSIS_CHAIN_ID || chainId == ARC_TESTNET_CHAIN_ID || chainId == POLYGON_CHAIN_ID
            || chainId == POLYGON_AMOY_CHAIN_ID || chainId == ROBINHOOD_CHAIN_ID || chainId == SONEIUM_CHAIN_ID
            || chainId == HYVECHAIN_CHAIN_ID || chainId == UNICHAIN_CHAIN_ID || chainId == MONAD_CHAIN_ID;
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else if (isSupportedChain(chainId)) {
            return NetworkConfig({ entryPointAddress: ENTRYPOINT_ADDRESS });
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        console2.log("Deploying mocks...");
        vm.startBroadcast();
        EntryPoint entryPoint = new EntryPoint();
        vm.stopBroadcast();
        console2.log("Mocks deployed!");

        return NetworkConfig({ entryPointAddress: address(entryPoint) });
    }

}
