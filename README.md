# Whizy Protocol - Smart Contracts

A decentralized prediction market protocol with automated yield generation and auto-rebalancing through DeFi protocol integration.

## Overview

Whizy Protocol enables users to create and participate in prediction markets while automatically earning yield on their deposited collateral through integration with leading DeFi protocols like Aave, Compound, and Morpho. Users can delegate auto-rebalancing authority to backend operators for optimal yield management.

### Key Features

- **Yield-Generating Predictions**: Collateral automatically earns yield through DeFi protocols
- **ERC4626 Vault Architecture**: Each market has its own vault for transparent asset management
- **Multi-Protocol Integration**: Supports Aave, Compound, and Morpho with automatic best-yield selection
- **Delegated Auto-Rebalancing**: Non-custodial delegation allowing operators to rebalance for optimal yields
- **Risk-Based Profiles**: Users choose low/medium/high risk profiles for personalized strategies
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

#### RebalancerDelegation
Non-custodial delegation contract allowing users to opt-in to automatic rebalancing.

**Key Features:**
- Users deposit USDC and enable auto-rebalancing with risk profiles (1=low, 2=medium, 3=high)
- Backend operators can rebalance user funds to optimal protocols
- Users maintain custody and can withdraw anytime
- Users can enable/disable auto-rebalancing without withdrawing

**Key Functions:**
- `depositAndEnable(amount, riskProfile)` - Deposit and enable auto-rebalancing
- `withdraw(amount)` - Withdraw funds (amount=0 for full withdrawal)
- `enableAutoRebalance(riskProfile)` - Enable auto-rebalancing with risk profile
- `disableAutoRebalance()` - Disable auto-rebalancing (funds remain deposited)
- `rebalance(user)` - Operator rebalances user's funds to best protocol
- `addOperator(operator)` - Owner adds authorized operator
- `removeOperator(operator)` - Owner removes operator

### Architecture Benefits

1. **Per-Market Vaults**: Each market has its own ERC4626 vault for clean accounting
2. **Automatic Yield**: Collateral is automatically deployed to highest-yielding protocols
3. **Delegated Rebalancing**: Non-custodial architecture with user-controlled auto-rebalancing
4. **Share-Based Accounting**: ERC4626 standard ensures accurate yield distribution
5. **Protocol Abstraction**: Adapters provide consistent interface across different DeFi protocols
6. **Risk Management**: Users control their risk appetite with configurable risk profiles

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

6. **RebalancerDelegation**
   - Non-custodial auto-rebalancing contract
   - Connect to ProtocolSelector and USDC
   - Add authorized operators for backend

## Usage Examples

### Using RebalancerDelegation

#### User: Deposit and Enable Auto-Rebalancing

```solidity
// Approve USDC for delegation contract
usdc.approve(address(rebalancerDelegation), 1000e6);

// Deposit and enable auto-rebalancing with low risk profile
rebalancerDelegation.depositAndEnable(1000e6, 1); // 1=low, 2=medium, 3=high

// Check user configuration
(bool enabled, uint8 risk, uint256 deposited) = rebalancerDelegation.userConfigs(userAddress);
```

#### User: Withdraw Funds

```solidity
// Withdraw specific amount
rebalancerDelegation.withdraw(500e6);

// Withdraw all (pass deposited amount or calculate from balance)
uint256 userBalance = protocolSelector.getTotalBalance(address(rebalancerDelegation), usdc);
rebalancerDelegation.withdraw(userBalance);
```

#### User: Enable/Disable Auto-Rebalancing

```solidity
// Disable auto-rebalancing (funds remain deposited)
rebalancerDelegation.disableAutoRebalance();

// Re-enable with different risk profile
rebalancerDelegation.enableAutoRebalance(2); // Switch to medium risk
```

#### Operator: Rebalance User Funds

```solidity
// Backend operator rebalances user to best protocol
rebalancerDelegation.rebalance(userAddress);
```

#### Owner: Manage Operators

```solidity
// Add new operator
rebalancerDelegation.addOperator(operatorAddress);

// Remove operator
rebalancerDelegation.removeOperator(operatorAddress);
```

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

# Run delegation tests
forge test --match-contract RebalancerDelegationTest

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
- Delegation contract operations (deposit, withdraw, enable/disable)
- Operator-based rebalancing
- Access control and authorization
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
- Operator-based rebalancing with authorization checks
- Users can enable/disable auto-rebalancing at any time
- Emergency withdrawal capabilities

### Reentrancy Protection
- ReentrancyGuard on all external functions
- Checks-Effects-Interactions pattern

### Yield Protocol Risks
- Protocol failures handled gracefully
- Automatic fallback to vault-only storage
- Individual protocol risk assessments
- User-controlled risk profiles for personalized strategies

### Non-Custodial Architecture
- Users maintain custody of their funds
- Operators can only rebalance, not withdraw user funds
- Users can withdraw anytime regardless of auto-rebalance status
- Transparent on-chain configuration and balances

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
