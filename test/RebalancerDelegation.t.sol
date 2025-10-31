// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RebalancerDelegation} from "../src/RebalancerDelegation.sol";
import {ProtocolSelector} from "../src/ProtocolSelector.sol";
import {USDC} from "../src/mocks/USDC.sol";
import {AaveFork} from "../src/forks/AaveFork.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";

contract RebalancerDelegationTest is Test {
    RebalancerDelegation public rebalancer;
    ProtocolSelector public protocolSelector;
    USDC public usdc;
    AaveFork public aaveFork;
    AaveAdapter public aaveAdapter;

    address public owner;
    address public operator;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        operator = makeAddr("operator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        usdc = new USDC(1000000 * 1e6);

        aaveFork = new AaveFork();
        aaveFork.initialize(1240, 100);

        aaveAdapter = new AaveAdapter(address(aaveFork));

        protocolSelector = new ProtocolSelector(200, 5);
        protocolSelector.registerProtocol(1, address(aaveAdapter), 3);

        rebalancer = new RebalancerDelegation(
            address(protocolSelector),
            address(usdc)
        );

        rebalancer.addOperator(operator);

        usdc.transfer(user1, 10000 * 1e6);
        usdc.transfer(user2, 5000 * 1e6);
    }

    function testDeployment() public view {
        assertEq(
            address(rebalancer.PROTOCOL_SELECTOR()),
            address(protocolSelector)
        );
        assertEq(address(rebalancer.USDC()), address(usdc));
        assertEq(rebalancer.owner(), owner);
        assertTrue(rebalancer.operators(owner));
        assertTrue(rebalancer.operators(operator));
    }

    function testDepositAndEnable() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);

        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);

        vm.stopPrank();

        (bool enabled, uint8 risk, uint256 deposited) = rebalancer.userConfigs(
            user1
        );
        assertTrue(enabled);
        assertEq(risk, 1);
        assertEq(deposited, depositAmount);
    }

    function testCannotDepositZero() public {
        vm.startPrank(user1);
        usdc.approve(address(rebalancer), 1000 * 1e6);

        vm.expectRevert("Amount must be > 0");
        rebalancer.depositAndEnable(0, 1);

        vm.stopPrank();
    }

    function testCannotDepositInvalidRiskProfile() public {
        vm.startPrank(user1);
        usdc.approve(address(rebalancer), 1000 * 1e6);

        vm.expectRevert("Invalid risk profile");
        rebalancer.depositAndEnable(1000 * 1e6, 0);

        vm.expectRevert("Invalid risk profile");
        rebalancer.depositAndEnable(1000 * 1e6, 4);

        vm.stopPrank();
    }

    function testRebalanceByOperator() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);
        vm.stopPrank();

        vm.prank(operator);
        rebalancer.rebalance(user1);
    }

    function testCannotRebalanceIfNotOperator() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(RebalancerDelegation.NotOperator.selector);
        rebalancer.rebalance(user1);
    }

    function testCannotRebalanceIfAutoRebalanceDisabled() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);

        rebalancer.disableAutoRebalance();
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(RebalancerDelegation.AutoRebalanceNotEnabled.selector);
        rebalancer.rebalance(user1);
    }

    function testWithdraw() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);

        uint256 balanceBefore = usdc.balanceOf(user1);

        rebalancer.withdraw(depositAmount);

        uint256 balanceAfter = usdc.balanceOf(user1);

        vm.stopPrank();

        assertGt(balanceAfter, balanceBefore);
    }

    function testWithdrawSpecificAmount() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);

        rebalancer.withdraw(depositAmount);

        vm.stopPrank();

        (, , uint256 deposited) = rebalancer.userConfigs(user1);
        assertEq(deposited, 0);
    }

    function testEnableAndDisableAutoRebalance() public {
        uint256 depositAmount = 1000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rebalancer), depositAmount);
        rebalancer.depositAndEnable(depositAmount, 1);

        rebalancer.disableAutoRebalance();
        (bool enabled1, , ) = rebalancer.userConfigs(user1);
        assertFalse(enabled1);

        rebalancer.enableAutoRebalance(2);
        (bool enabled2, uint8 risk, ) = rebalancer.userConfigs(user1);
        assertTrue(enabled2);
        assertEq(risk, 2);

        vm.stopPrank();
    }

    function testAddAndRemoveOperator() public {
        address newOperator = makeAddr("newOperator");

        rebalancer.addOperator(newOperator);
        assertTrue(rebalancer.operators(newOperator));

        rebalancer.removeOperator(newOperator);
        assertFalse(rebalancer.operators(newOperator));
    }

    function testCannotAddOperatorIfNotOwner() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(user1);
        vm.expectRevert(RebalancerDelegation.NotOwner.selector);
        rebalancer.addOperator(newOperator);
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        rebalancer.transferOwnership(newOwner);
        assertEq(rebalancer.owner(), newOwner);
    }

    function testMultipleUsersDeposit() public {
        vm.startPrank(user1);
        usdc.approve(address(rebalancer), 2000 * 1e6);
        rebalancer.depositAndEnable(2000 * 1e6, 1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(rebalancer), 1500 * 1e6);
        rebalancer.depositAndEnable(1500 * 1e6, 3);
        vm.stopPrank();

        (bool enabled1, uint8 risk1, uint256 deposited1) = rebalancer
            .userConfigs(user1);
        assertTrue(enabled1);
        assertEq(risk1, 1);
        assertEq(deposited1, 2000 * 1e6);

        (bool enabled2, uint8 risk2, uint256 deposited2) = rebalancer
            .userConfigs(user2);
        assertTrue(enabled2);
        assertEq(risk2, 3);
        assertEq(deposited2, 1500 * 1e6);
    }
}
