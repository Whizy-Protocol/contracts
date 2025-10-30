#!/bin/bash

# WHIZY Testnet Deployment Script for Whizy Prediction Market
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  Whizy - WHIZY Testnet Deployment${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

# Load environment variables
if [ -f .env ]; then
    source .env
    echo -e "${GREEN}✓ Environment variables loaded${NC}"
else
    echo -e "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Check required variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}✗ PRIVATE_KEY not set${NC}"
    exit 1
fi

if [ -z "$WHIZY_TESTNET_RPC_URL" ]; then
    echo -e "${RED}✗ WHIZY_TESTNET_RPC_URL not set${NC}"
    exit 1
fi

if [ -z "$WHIZY_EXPLORER_API_KEY" ]; then
    echo -e "${YELLOW}⚠ WHIZY_EXPLORER_API_KEY not set - verification will be skipped${NC}"
    VERIFY_FLAG=""
else
    VERIFY_FLAG="--verify --etherscan-api-key $WHIZY_EXPLORER_API_KEY"
fi

# Get deployer address
DEPLOYER=$(cast wallet address $PRIVATE_KEY)
echo -e "${BLUE}Deployer:${NC} $DEPLOYER"

# Check balance
BALANCE=$(cast balance $DEPLOYER --rpc-url $WHIZY_TESTNET_RPC_URL)
BALANCE_ETH=$(cast from-wei $BALANCE)
echo -e "${BLUE}Balance:${NC} $BALANCE_ETH ETH"
echo ""

if (( $(echo "$BALANCE_ETH < 0.05" | bc -l) )); then
    echo -e "${YELLOW}⚠ Warning: Low balance ($BALANCE_ETH ETH)${NC}"
    echo -e "${YELLOW}  You may need more WHIZY"
    echo ""
fi

echo -e "${YELLOW}Starting deployment...${NC}"
echo ""

# Deploy using forge script
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $WHIZY_TESTNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --legacy \
    --slow \
    --skip-simulation \
    $VERIFY_FLAG \
    -vvv

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}  Deployment Successful! 🎉${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo -e "${BLUE}View on WHIZYScan:${NC}"
    echo -e "  https://hashscan.io/testnet/account/$DEPLOYER"
    echo ""
    echo -e "${BLUE}Deployment artifacts:${NC}"
    echo -e "  broadcast/Deploy.s.sol/2484/run-latest.json"
    echo ""
else
    echo ""
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}  Deployment Failed ❌${NC}"
    echo -e "${RED}==========================================${NC}"
    exit 1
fi
