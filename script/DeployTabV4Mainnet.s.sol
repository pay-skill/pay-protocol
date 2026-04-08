// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {PayTabV4} from "../src/PayTabV4.sol";

/// @title DeployTabV4Mainnet
/// @notice Deploy ONLY PayTabV4 on Base mainnet against existing infrastructure.
///         Does NOT authorize on PayFee - that must be done via Gnosis Safe.
///
/// @dev Prerequisites:
///      - DEPLOYER_PRIVATE_KEY: deployer key (0x99De)
///      - BASE_MAINNET_RPC_URL: Base mainnet RPC
///      - FEE_WALLET: 0xc848c2adBC9e47F9788505cC1b405ef02045F281
///
///      After deployment:
///        1. Note the PayTabV4 address from logs
///        2. Authorize on PayFee via Gnosis Safe (authorize-tabv4.html)
///        3. Update server TAB_V2_ADDRESS env var
contract DeployTabV4Mainnet is Script {
    /// @dev USDC on Base mainnet.
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev PayFee proxy on Base mainnet.
    address constant PAY_FEE_PROXY = 0xafEeA7FF8253D161daEBA7BA86811fA47393013C;

    /// @dev Mainnet relayer (server signing key). NOT the deployer.
    address constant RELAYER = 0x7cB5d64A56b6E554DBA8E4FF8F4072c04dE01735;

    function run() external {
        address deployer = msg.sender;
        address feeWallet = vm.envAddress("FEE_WALLET");

        console2.log("=== PayTabV4 Deployment (Base Mainnet) ===");
        console2.log("Deployer:       ", deployer);
        console2.log("USDC:           ", USDC);
        console2.log("PayFee (proxy): ", PAY_FEE_PROXY);
        console2.log("Fee Wallet:     ", feeWallet);
        console2.log("Relayer:        ", RELAYER);
        console2.log("");

        vm.startBroadcast();

        // Deploy PayTabV4 (immutable) with correct relayer
        PayTabV4 tabV4 = new PayTabV4(USDC, PAY_FEE_PROXY, feeWallet, RELAYER);
        console2.log("PayTabV4:       ", address(tabV4));

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Next Steps ===");
        console2.log("1. Authorize PayTabV4 on PayFee via Gnosis Safe");
        console2.log("   PayFee.authorizeCaller(", address(tabV4), ")");
        console2.log("2. Update server .env:");
        console2.log("   TAB_V2_ADDRESS=", address(tabV4));
    }
}
