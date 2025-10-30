// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {USDC} from "../src/mocks/USDC.sol";
import {AccessControl} from "../src/AccessControl.sol";
import {WhizyPredictionMarket} from "../src/WhizyPredictionMarket.sol";
import {MarketVault} from "../src/MarketVault.sol";
import {ProtocolSelector} from "../src/ProtocolSelector.sol";
import {AaveFork} from "../src/forks/AaveFork.sol";
import {AaveAdapter} from "../src/adapters/AaveAdapter.sol";
import {MorphoFork} from "../src/forks/MorphoFork.sol";
import {MorphoAdapter} from "../src/adapters/MorphoAdapter.sol";

contract WhizyPredictionMarketTest is Test {
    USDC public usdc;
    AccessControl public accessControl;
    WhizyPredictionMarket public market;
    ProtocolSelector public protocolSelector;
    AaveFork public aaveFork;
    AaveAdapter public aaveAdapter;

    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);

    uint256 constant INITIAL_SUPPLY = 1000000 * 1e6;
    uint256 constant USER_BALANCE = 10000 * 1e6;

    function setUp() public {
        vm.startPrank(owner);

        usdc = new USDC(INITIAL_SUPPLY);
        accessControl = new AccessControl();

        aaveFork = new AaveFork();
        aaveFork.initialize(500, 100);

        aaveAdapter = new AaveAdapter(address(aaveFork));

        protocolSelector = new ProtocolSelector(200, 5);
        protocolSelector.registerProtocol(1, address(aaveAdapter), 3);

        market = new WhizyPredictionMarket(address(accessControl), address(protocolSelector));

        usdc.mint(alice, USER_BALANCE);
        usdc.mint(bob, USER_BALANCE);

        vm.stopPrank();
    }

    function test_CreateMarket() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        (uint256 id, string memory question,, address token, MarketVault vault,,,,,) = market.markets(marketId);

        assertEq(id, 0);
        assertEq(question, "Will ETH reach $5000?");
        assertEq(token, address(usdc));
        assertTrue(address(vault) != address(0), "Vault should be deployed");
    }

    function test_PlaceBet() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        uint256 betAmount = 1000 * 1e6;
        vm.startPrank(alice);
        usdc.approve(address(market), betAmount);
        market.placeBet(marketId, true, betAmount);
        vm.stopPrank();

        (uint256 yesShares, uint256 noShares, bool claimed) = market.positions(marketId, alice);

        assertTrue(yesShares > 0, "Alice should have YES shares");
        assertEq(noShares, 0, "Alice should have no NO shares");
        assertFalse(claimed, "Should not be claimed");

        assertEq(usdc.balanceOf(alice), USER_BALANCE - betAmount);
    }

    function test_PlaceBetBothSides() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        uint256 aliceBet = 1000 * 1e6;
        vm.startPrank(alice);
        usdc.approve(address(market), aliceBet);
        market.placeBet(marketId, true, aliceBet);
        vm.stopPrank();

        uint256 bobBet = 2000 * 1e6;
        vm.startPrank(bob);
        usdc.approve(address(market), bobBet);
        market.placeBet(marketId, false, bobBet);
        vm.stopPrank();

        (uint256 aliceYes,,) = market.positions(marketId, alice);
        (, uint256 bobNo,) = market.positions(marketId, bob);

        assertTrue(aliceYes > 0);
        assertTrue(bobNo > 0);
    }

    function test_ResolveMarket() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);

        vm.prank(owner);
        market.resolveMarket(marketId, true);

        (,,,,,,, bool resolved, bool outcome,) = market.markets(marketId);
        assertTrue(resolved);
        assertTrue(outcome);
    }

    function test_ClaimWinnings() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 2000 * 1e6);
        market.placeBet(marketId, false, 2000 * 1e6);
        vm.stopPrank();

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.warp(block.timestamp + 31 days);
        vm.prank(owner);
        market.resolveMarket(marketId, true);

        vm.prank(alice);
        market.claimWinnings(marketId);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        assertTrue(aliceBalanceAfter > aliceBalanceBefore, "Alice should profit");

        (,, bool claimed) = market.positions(marketId, alice);
        assertTrue(claimed);
    }

    function test_YieldAccrual() public {
        console.log("\n=== YIELD ACCRUAL TEST ===\n");

        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 365 days, address(usdc));

        (,,,, MarketVault vault,,,,,) = market.markets(marketId);

        uint256 aliceBet = 1000 * 1e6;
        uint256 bobBet = 2000 * 1e6;

        vm.startPrank(alice);
        usdc.approve(address(market), aliceBet);
        market.placeBet(marketId, true, aliceBet);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), bobBet);
        market.placeBet(marketId, false, bobBet);
        vm.stopPrank();

        uint256 totalAssetsInitial = vault.totalAssets();
        uint256 totalSharesInitial = vault.totalSupply();

        console.log("Initial total assets:", totalAssetsInitial);
        console.log("Initial total shares:", totalSharesInitial);
        console.log("Fee percentage:", market.feePercentage());

        vm.warp(block.timestamp + 30 days);
        aaveFork.accrueYield(usdc);

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 yieldEarned = vault.getCurrentYield();

        console.log("\nAfter 30 days:");
        console.log("Total assets:", totalAssetsAfter);
        console.log("Yield earned:", yieldEarned);

        assertTrue(yieldEarned > 0, "Should have earned yield");
        assertTrue(totalAssetsAfter > totalAssetsInitial, "Assets should have grown");
    }

    function test_WinnerGetsYield() public {
        console.log("\n=== WINNER GETS YIELD TEST ===\n");

        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 365 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 2000 * 1e6);
        market.placeBet(marketId, false, 2000 * 1e6);
        vm.stopPrank();

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.warp(block.timestamp + 30 days);
        aaveFork.accrueYield(usdc);

        (,,,, MarketVault vault,,,,,) = market.markets(marketId);
        uint256 yieldBeforeClaim = vault.getCurrentYield();

        console.log("Yield before resolution:", yieldBeforeClaim);

        vm.warp(block.timestamp + 335 days);
        aaveFork.accrueYield(usdc);

        vm.prank(owner);
        market.resolveMarket(marketId, true);

        vm.prank(alice);
        market.claimWinnings(marketId);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);
        uint256 aliceProfit = aliceBalanceAfter - aliceBalanceBefore;

        console.log("Alice balance before:", aliceBalanceBefore);
        console.log("Alice balance after:", aliceBalanceAfter);
        console.log("Alice profit:", aliceProfit);

        assertTrue(aliceProfit >= 2000 * 1e6, "Alice should get at least 2000 USDC");
        assertTrue(aliceProfit > 2000 * 1e6, "Alice should profit from yield");
    }

    function test_LoserGetsYield() public {
        console.log("\n=== LOSER GETS YIELD TEST ===\n");

        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 365 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 2000 * 1e6);
        market.placeBet(marketId, false, 2000 * 1e6);
        vm.stopPrank();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.warp(block.timestamp + 365 days);
        aaveFork.accrueYield(usdc);

        (,,,, MarketVault vault,,,,,) = market.markets(marketId);
        uint256 yieldBeforeClaim = vault.getCurrentYield();
        console.log("Total yield accrued:", yieldBeforeClaim);

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        market.resolveMarket(marketId, true);

        vm.prank(bob);
        market.claimWinnings(marketId);

        uint256 bobBalanceAfter = usdc.balanceOf(bob);
        uint256 bobPayout = bobBalanceAfter - bobBalanceBefore;

        console.log("Bob balance before:", bobBalanceBefore);
        console.log("Bob balance after:", bobBalanceAfter);
        console.log("Bob payout (yield only):", bobPayout);

        assertTrue(bobPayout > 0, "Loser should get yield");
        assertTrue(bobPayout < 1980 * 1e6, "Loser should only get yield, not principal");
    }

    function test_GetPotentialPayout() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 2000 * 1e6);
        market.placeBet(marketId, false, 2000 * 1e6);
        vm.stopPrank();

        (uint256 yesPayoutIfWin, uint256 noPayoutIfWin, uint256 currentYield) =
            market.getPotentialPayout(marketId, alice);

        console.log("Alice YES payout if win:", yesPayoutIfWin);
        console.log("Alice NO payout if win:", noPayoutIfWin);
        console.log("Current yield:", currentYield);

        assertTrue(yesPayoutIfWin > 0, "Alice should have YES payout");
        assertEq(noPayoutIfWin, 0, "Alice has no NO position");
    }

    function test_CannotClaimTwice() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        vm.prank(owner);
        market.resolveMarket(marketId, true);

        vm.prank(alice);
        market.claimWinnings(marketId);

        vm.prank(alice);
        vm.expectRevert("Already claimed");
        market.claimWinnings(marketId);
    }

    function test_CannotBetAfterEnd() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        vm.warp(block.timestamp + 31 days);

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        vm.expectRevert("Market ended");
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();
    }

    function test_CannotResolveBeforeEnd() public {
        vm.prank(owner);
        uint256 marketId = market.createMarket("Will ETH reach $5000?", block.timestamp + 30 days, address(usdc));

        vm.prank(owner);
        vm.expectRevert("Market not ended");
        market.resolveMarket(marketId, true);
    }

    function test_MultipleProtocols() public {
        console.log("\n=== MULTIPLE PROTOCOLS TEST ===\n");

        vm.startPrank(owner);

        MorphoFork morphoFork = new MorphoFork();
        morphoFork.initialize(600, 100);
        MorphoAdapter morphoAdapter = new MorphoAdapter(address(morphoFork));

        morphoFork.addToWhitelist(address(morphoAdapter));
        morphoAdapter.authorizeCaller(address(protocolSelector));

        protocolSelector.registerProtocol(2, address(morphoAdapter), 4);

        vm.stopPrank();

        console.log("Registered protocols:");
        console.log("  - Aave: 5% APY, risk level 3");
        console.log("  - Morpho: 6% APY, risk level 4");
        console.log("ProtocolSelector will choose based on score formula");

        vm.prank(owner);
        uint256 marketId = market.createMarket("Will BTC reach $100k?", block.timestamp + 365 days, address(usdc));

        vm.startPrank(alice);
        usdc.approve(address(market), 1000 * 1e6);
        market.placeBet(marketId, true, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(market), 2000 * 1e6);
        market.placeBet(marketId, false, 2000 * 1e6);
        vm.stopPrank();

        console.log("\nBets placed, accruing yield...");

        vm.warp(block.timestamp + 365 days);
        aaveFork.accrueYield(usdc);
        morphoFork.accrueYield(address(usdc));

        (,,,, MarketVault vault,,,,,) = market.markets(marketId);
        uint256 yieldFinal = vault.getCurrentYield();
        console.log("\nTotal yield after 365 days:", yieldFinal);

        vm.prank(owner);
        market.resolveMarket(marketId, true);

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 bobBalanceBefore = usdc.balanceOf(bob);

        vm.prank(alice);
        market.claimWinnings(marketId);

        vm.prank(bob);
        market.claimWinnings(marketId);

        uint256 alicePayout = usdc.balanceOf(alice) - aliceBalanceBefore;
        uint256 bobPayout = usdc.balanceOf(bob) - bobBalanceBefore;

        console.log("\nPayouts:");
        console.log("  Alice (winner):", alicePayout, "USDC (her principal + yield + Bob's principal)");
        console.log("  Bob (loser):", bobPayout, "USDC (yield only)");

        assertTrue(alicePayout >= 2000 * 1e6, "Alice should get at least 2000 USDC");
        assertTrue(alicePayout < 2970 * 1e6, "Alice gets less than full 2970 since Bob keeps yield");

        assertTrue(bobPayout > 0, "Bob should get some yield");
        assertTrue(bobPayout < 1980 * 1e6, "Bob should only get yield, not principal");

        assertTrue(yieldFinal > 0, "Yield should have accrued in selected protocol");

        uint256 totalPaid = alicePayout + bobPayout;
        console.log("\nTotal paid out:", totalPaid, "USDC");
        console.log("Expected (2970 + yield):", 2970 * 1e6 + yieldFinal, "USDC");

        console.log("\n[PASS] Multi-protocol system working correctly");
    }
}
