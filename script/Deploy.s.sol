// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {WhizyPredictionMarket} from "../src/WhizyPredictionMarket.sol";
import {AccessControl} from "../src/AccessControl.sol";
import {ProtocolSelector} from "../src/ProtocolSelector.sol";
import {USDC} from "../src/mocks/USDC.sol";
import {AaveFork} from "../src/forks/AaveFork.sol";
import {CompoundFork} from "../src/forks/CompoundFork.sol";
import {MorphoFork} from "../src/forks/MorphoFork.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";
import {CompoundAdapter} from "../src/adapters/CompoundAdapter.sol";
import {MorphoAdapter} from "../src/adapters/MorphoAdapter.sol";
import {RebalancerDelegation} from "../src/RebalancerDelegation.sol";

contract DeployScript is Script {
    AccessControl public accessControl;
    ProtocolSelector public protocolSelector;
    WhizyPredictionMarket public market;
    USDC public usdc;

    AaveFork public aaveFork;
    MorphoFork public morphoFork;
    CompoundFork public compoundFork;

    AaveAdapter public aaveAdapter;
    MorphoAdapter public morphoAdapter;
    CompoundAdapter public compoundAdapter;

    RebalancerDelegation public rebalancer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Whizy Prediction Market Deployment ===");
        console.log("Deploying with address:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        deployCore();
        deployProtocols();
        deployAdapters();
        deployMarket();
        deployRebalancer(deployer);

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("");
        console.log("Core Contracts:");
        console.log("  AccessControl:        ", address(accessControl));
        console.log("  ProtocolSelector:     ", address(protocolSelector));
        console.log("  PredictionMarket:     ", address(market));
        console.log("  RebalancerDelegation: ", address(rebalancer));
        console.log("");
        console.log("Mock Token:");
        console.log("  USDC:                 ", address(usdc));
        console.log("");
        console.log("Yield Protocols:");
        console.log("  Aave:");
        console.log("    - Fork:       ", address(aaveFork));
        console.log("    - Adapter:    ", address(aaveAdapter));
        console.log("    - APY:         12.4%");
        console.log("    - Risk Level:  3/10");
        console.log("  Morpho:");
        console.log("    - Fork:       ", address(morphoFork));
        console.log("    - Adapter:    ", address(morphoAdapter));
        console.log("    - APY:         6.2%");
        console.log("    - Risk Level:  4/10");
        console.log("  Compound:");
        console.log("    - Fork:       ", address(compoundFork));
        console.log("    - Adapter:    ", address(compoundAdapter));
        console.log("    - APY:         4.8%");
        console.log("    - Risk Level:  2/10");
        console.log("");
        console.log("Configuration:");
        console.log("  Market Fee:            1%");
        console.log("  Min APY Threshold:     2%");
        console.log("  Max Risk Tolerance:    5");
        console.log("  Best APY:              Aave at 12.4%");
        console.log("  Lowest Risk:           Compound at 2/10");
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
    }

    function deployCore() internal {
        console.log("1. Deploying Core Contracts...");
        accessControl = new AccessControl();
        console.log("   AccessControl:", address(accessControl));

        usdc = new USDC(1000000 * 1e6);
        console.log("   Mock USDC:", address(usdc));
    }

    function deployProtocols() internal {
        console.log("\n2. Deploying Yield Protocols...");

        aaveFork = new AaveFork();
        aaveFork.initialize(1240, 100);
        console.log("   AaveFork:             ", address(aaveFork));
        console.log("   - APY: 12.4%");

        morphoFork = new MorphoFork();
        morphoFork.initialize(620, 100);
        console.log("   MorphoFork:           ", address(morphoFork));
        console.log("   - APY: 6.2%");

        compoundFork = new CompoundFork();
        compoundFork.initialize(480, 100);
        console.log("   CompoundFork:         ", address(compoundFork));
        console.log("   - APY: 4.8%");
    }

    function deployAdapters() internal {
        console.log("\n3. Deploying Adapters...");

        aaveAdapter = new AaveAdapter(address(aaveFork));
        console.log("   AaveAdapter:", address(aaveAdapter));

        morphoAdapter = new MorphoAdapter(address(morphoFork));
        morphoFork.addToWhitelist(address(morphoAdapter));
        console.log("   MorphoAdapter:", address(morphoAdapter));

        compoundAdapter = new CompoundAdapter(address(compoundFork));
        console.log("   CompoundAdapter:", address(compoundAdapter));
    }

    function deployMarket() internal {
        console.log("\n4. Deploying Market & Selector...");

        protocolSelector = new ProtocolSelector(200, 5);
        console.log("   ProtocolSelector:     ", address(protocolSelector));
        console.log("   - Min APY Threshold:   2%");
        console.log("   - Max Risk Tolerance:  5");
        console.log("");

        console.log("   Registering Protocols:");

        protocolSelector.registerProtocol(1, address(aaveAdapter), 3);
        console.log("   [OK] Aave (Type 1):");
        console.log("     - Adapter:  ", address(aaveAdapter));
        console.log("     - Protocol: ", address(aaveFork));
        console.log("     - APY:       12.4%");
        console.log("     - Risk:      3/10 (Medium)");

        protocolSelector.registerProtocol(2, address(morphoAdapter), 4);
        morphoAdapter.authorizeCaller(address(protocolSelector));
        console.log("   [OK] Morpho (Type 2):");
        console.log("     - Adapter:  ", address(morphoAdapter));
        console.log("     - Protocol: ", address(morphoFork));
        console.log("     - APY:       6.2%");
        console.log("     - Risk:      4/10 (Medium-High)");

        protocolSelector.registerProtocol(3, address(compoundAdapter), 2);
        console.log("   [OK] Compound (Type 3):");
        console.log("     - Adapter:  ", address(compoundAdapter));
        console.log("     - Protocol: ", address(compoundFork));
        console.log("     - APY:       4.8%");
        console.log("     - Risk:      2/10 (Low-Medium)");
        console.log("");
        console.log("   All 3 protocols registered successfully!");
        console.log("");

        market = new WhizyPredictionMarket(
            address(accessControl),
            address(protocolSelector)
        );
        console.log("   PredictionMarket:     ", address(market));
    }

    function deployRebalancer(address deployer) internal {
        console.log("\n5. Deploying RebalancerDelegation...");

        rebalancer = new RebalancerDelegation(
            address(protocolSelector),
            address(usdc)
        );
        console.log("   RebalancerDelegation: ", address(rebalancer));
        console.log("   - Owner:               ", deployer);
        console.log("   - Default Operator:    ", deployer);
        console.log("");

        console.log("   Setting up operators...");
        market.addOperator(deployer);
        console.log("   [OK] Deployer added as market operator");
        console.log("   - Can rebalance market vaults");
        console.log("   - Can rebalance user deposits");
        console.log("");
    }
}
