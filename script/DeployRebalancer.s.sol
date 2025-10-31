// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RebalancerDelegation} from "../src/RebalancerDelegation.sol";

contract DeployRebalancer is Script {
    address constant PROTOCOL_SELECTOR =
        0x0371aB2d90A436C8E5c5B6aF8835F46A6Ce884Ba;
    address constant USDC = 0x8bc6E87bE188B7964E48f37d7A2c144416a995eE;
    address constant ACCESS_CONTROL =
        0x62013Ec34fe3A074AC5cA5fCeDc0EFa646A5445B;

    RebalancerDelegation public rebalancer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== RebalancerDelegation Deployment ===");
        console.log("Deploying with address:", deployer);
        console.log("");
        console.log("Using existing contracts:");
        console.log("  ProtocolSelector:", PROTOCOL_SELECTOR);
        console.log("  USDC Token:      ", USDC);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        deployRebalancer();

        vm.stopBroadcast();

        printSummary(deployer);
    }

    function deployRebalancer() internal {
        console.log("1. Deploying RebalancerDelegation...");

        rebalancer = new RebalancerDelegation(PROTOCOL_SELECTOR, USDC);

        console.log("   RebalancerDelegation:", address(rebalancer));
        console.log("   - Owner:   ", rebalancer.owner());
        console.log("   - Connected to ProtocolSelector");
        console.log("   - Using USDC token");
    }

    function printSummary(address deployer) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("");
        console.log("RebalancerDelegation Contract:");
        console.log("  Address:              ", address(rebalancer));
        console.log("  Owner:                ", rebalancer.owner());
        console.log("  Default Operator:     ", deployer);
        console.log("");
        console.log("Connected Contracts:");
        console.log("  ProtocolSelector:     ", PROTOCOL_SELECTOR);
        console.log("  USDC Token:           ", USDC);
        console.log("");
        console.log("Configuration:");
        console.log("  Auto-Rebalancing:      Enabled");
        console.log("  Risk Profiles:         Low (1), Medium (2), High (3)");
        console.log("  User Withdrawals:      Anytime");
        console.log("");
        console.log("=== Add to Backend .env ===");
        console.log("REBALANCER_DELEGATION_ADDRESS=%s", address(rebalancer));
        console.log("OPERATOR_PRIVATE_KEY=<your_backend_wallet_key>");
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
    }
}
