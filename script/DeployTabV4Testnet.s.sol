// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {PayFee} from "../src/PayFee.sol";
import {PayTabV4} from "../src/PayTabV4.sol";

/// @title DeployTabV4Testnet
/// @notice Deploy ONLY PayTabV4 on Base Sepolia against existing infrastructure.
///         Reads existing contract addresses from environment.
///
/// @dev Prerequisites:
///      - DEPLOYER_PRIVATE_KEY: same deployer as original deploy
///      - ALCHEMY_BASE_SEPOLIA_URL: Base Sepolia RPC
///      - PAY_FEE_ADDRESS: existing PayFee proxy address
///      - USDC_ADDRESS: existing MockUSDC address
///      - FEE_WALLET: existing fee wallet (defaults to deployer)
///
///      Changes from V3:
///        - Per-charge fee floor: max(chargesNew * MIN_CHARGE_FEE, rateBps)
///        - New _chargeCountAtLastWithdrawal mapping for withdrawal window tracking
contract DeployTabV4Testnet is Script {
    function run() external {
        address deployer = msg.sender;

        // Read existing addresses from env
        address usdc = vm.envAddress("USDC_ADDRESS");
        address payFeeProxy = vm.envAddress("PAY_FEE_ADDRESS");
        address feeWallet = vm.envOr("FEE_WALLET", deployer);

        console2.log("=== PayTabV4 Deployment (Base Sepolia) ===");
        console2.log("Deployer:       ", deployer);
        console2.log("USDC:           ", usdc);
        console2.log("PayFee (proxy): ", payFeeProxy);
        console2.log("Fee Wallet:     ", feeWallet);
        console2.log("");

        vm.startBroadcast();

        // Deploy PayTabV4 (immutable)
        PayTabV4 tabV4 = new PayTabV4(usdc, payFeeProxy, feeWallet, deployer);
        console2.log("PayTabV4:       ", address(tabV4));

        // Authorize PayTabV4 to call recordTransaction on PayFee
        PayFee(payFeeProxy).authorizeCaller(address(tabV4));
        console2.log("PayFee: authorized PayTabV4");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Done ===");
        console2.log("Update server .env:");
        console2.log("TAB_V2_ADDRESS=", address(tabV4));
    }
}
