# Whizy Protocol - Smart Contracts

A decentralized prediction market protocol with automated yield generation through DeFi protocol integration.

## Overview

Whizy Protocol enables users to create and participate in prediction markets while automatically earning yield on their deposited collateral through integration with leading DeFi protocols like Aave, Compound, and Morpho.

### Key Features

- **Yield-Generating Predictions**: Collateral automatically earns yield through DeFi protocols
- **ERC4626 Vault Architecture**: Each market has its own vault for transparent asset management
- **Multi-Protocol Integration**: Supports Aave, Compound, and Morpho with automatic best-yield selection
- **Fair Reward Distribution**: Winners receive their stake plus loser's stake plus proportional yield
- **Gas-Optimized Design**: Minimal overhead with efficient share-based accounting

## Architecture

### Core Contracts

#### WhizyPredictionMarket
The main contract that orchestrates prediction markets with automatic yield generation.

**Key Functions:**
- `createMarket(question, endTime, token)` - Creates a new prediction market
- `placeBet(marketId, isYes, amount)` - Places a YES/NO bet with automatic yield deployment
- `resolveMarket(marketId, outcome)` - Resolves market with final outcome
- `claimWinnings(marketId)` - Claims winnings including principal, opponent stakes, and yield

#### MarketVault (ERC4626)
Individual vault for each market that manages collateral and yield generation.

**Key Functions:**
- `depositForMarket(assets)` - Deposits assets and deploys to yield protocols
- `withdrawForMarket(assets, recipient)` - Withdraws assets from protocols if needed
- `getCurrentYield()` - Returns current unrealized yield
- `totalAssets()` - Returns total assets including yield from protocols

#### ProtocolSelector
Intelligent protocol selection system that automatically chooses the best yield protocol.

**Selection Criteria:**
- APY (50% weight)
- TVL/Liquidity (30% weight)  
- Risk Level (20% weight)

**Supported Protocols:**
- Aave (Type 1)
- Morpho (Type 2)
- Compound (Type 3)

### Architecture Benefits

1. **Per-Market Vaults**: Each market has its own ERC4626 vault for clean accounting
2. **Automatic Yield**: Collateral is automatically deployed to highest-yielding protocols
3. **Share-Based Accounting**: ERC4626 standard ensures accurate yield distribution
4. **Protocol Abstraction**: Adapters provide consistent interface across different DeFi protocols

## Contract Deployment

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install
```

### Deployment Script

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key_here
export RPC_URL=your_rpc_url_here

# Deploy to network
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

### Deployment Order

1. **Core Contracts**
   - AccessControl
   - Mock USDC (testnet only)

2. **Yield Protocols** 
   - AaveFork, MorphoFork, CompoundFork
   - Initialize with respective APYs (12.4%, 6.2%, 4.8%)

3. **Protocol Adapters**
   - AaveAdapter, MorphoAdapter, CompoundAdapter
   - Standardized IYieldProtocol interface

4. **Protocol Selector**
   - Register all protocols with risk levels
   - Configure thresholds (2% min APY, 5 max risk)

5. **Prediction Market**
   - Main contract linking all components

## Usage Examples

### Creating a Market

```solidity
// Create market (owner only)
string memory question = "Will ETH reach $5000 by end of year?";
uint256 endTime = block.timestamp + 365 days;
address token = address(usdc);

uint256 marketId = market.createMarket(question, endTime, token);
```

### Placing Bets

```solidity
// Approve tokens
usdc.approve(address(market), 1000e6);

// Place YES bet
market.placeBet(marketId, true, 1000e6);

// Place NO bet  
market.placeBet(marketId, false, 2000e6);
```

### Resolving and Claiming

```solidity
// Wait for market end time
// vm.warp(endTime + 1);

// Resolve market (owner only)
market.resolveMarket(marketId, true); // YES outcome

// Winners claim rewards
market.claimWinnings(marketId);
```

## Yield Distribution Model

### Winner Rewards
Winners receive:
1. **Original stake** (their principal)
2. **Loser's principal** (proportional to their share of winning side)
3. **Proportional yield** (from the entire pool)

### Loser Compensation
Losers receive:
- **Yield only** (compensation for providing liquidity and taking risk)

### Example Calculation

```
Market: $10,000 total pool
- Alice bets $3,000 YES
- Bob bets $7,000 NO
- Outcome: YES wins
- Total yield earned: $500

Alice (winner) receives:
- Principal: $3,000
- Share of losing stakes: $7,000 
- Share of yield: $500
- Total: $10,500

Bob (loser) receives:
- Principal: $0
- Yield compensation: $0 (all yield goes to winners in this model)
- Total: $0
```

## Testing

### Run Tests

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vv

# Run specific test
forge test --match-test test_YieldAccrual

# Generate coverage report
forge coverage
```

### Test Coverage

- Market creation and validation
- Bet placement and position tracking
- Market resolution and outcome setting
- Yield accrual and distribution
- Winner/loser payout calculations
- Protocol selection and yield optimization
- Emergency functions and access control

## Configuration

### Default Parameters

```solidity
// Market fees
feePercentage = 100; // 1%

// Protocol selector thresholds
minApyThreshold = 200; // 2%
maxRiskTolerance = 5;  // Medium risk

// Protocol risk levels
Aave: 3/10     // Medium risk
Morpho: 4/10   // Medium-high risk  
Compound: 2/10 // Low-medium risk
```

### Customization

Owners can update:
- Fee percentages (max 10%)
- APY thresholds
- Risk tolerance levels
- Protocol active status
- Protocol registrations

## Security Considerations

### Access Control
- Owner-only functions for market creation and resolution
- Protocol registration restricted to owners
- Emergency withdrawal capabilities

### Reentrancy Protection
- ReentrancyGuard on all external functions
- Checks-Effects-Interactions pattern

### Yield Protocol Risks
- Protocol failures handled gracefully
- Automatic fallback to vault-only storage
- Individual protocol risk assessments

### Precision and Rounding
- Share-based accounting prevents precision loss
- Conservative rounding in user's favor
- Tolerance for small withdrawal discrepancies

## Gas Optimization

- Single storage writes where possible
- Batch operations for protocol interactions
- Efficient share calculations using ERC4626
- Minimal external calls during betting

## Upgradeability

Current contracts are non-upgradeable by design for immutability and trust. Future versions may implement:
- Proxy patterns for core contracts
- Modular adapter system for new protocols
- Governance-controlled parameter updates

## License

MIT License - see LICENSE file for details.
