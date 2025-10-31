// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "./AccessControl.sol";
import {MarketVault} from "./MarketVault.sol";

/**
 * @title WhizyPredictionMarket
 * @dev Simplified prediction market with MarketVault for automatic yield generation
 *
 * Key improvements:
 * - Each market has its own MarketVault (ERC4626)
 * - Automatic yield through Protocol Selector + Adapters
 * - Simple position tracking (no ERC1155, just accounting)
 * - Clean separation of concerns
 */
contract WhizyPredictionMarket is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DEFAULT_FEE = 100;

    enum MarketStatus {
        Active,
        Resolved,
        Cancelled
    }

    struct Market {
        uint256 id;
        string question;
        uint256 endTime;
        address token;
        MarketVault vault;
        uint256 totalYesShares;
        uint256 totalNoShares;
        bool resolved;
        bool outcome;
        MarketStatus status;
    }

    struct Position {
        uint256 yesShares;
        uint256 noShares;
        bool claimed;
    }

    AccessControl public immutable ACCESS_CONTROL;
    address public protocolSelector;
    uint256 public feePercentage;
    address public feeRecipient;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Position)) public positions;
    uint256 public nextMarketId;

    event MarketCreated(
        uint256 indexed marketId,
        string question,
        uint256 endTime,
        address token,
        address vault
    );
    event BetPlaced(
        uint256 indexed marketId,
        address indexed user,
        bool position,
        uint256 amount,
        uint256 shares
    );
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event WinningsClaimed(
        uint256 indexed marketId,
        address indexed user,
        uint256 amount
    );

    error MarketNotFound();
    error MarketEnded();
    error MarketNotResolved();
    error InvalidAmount();
    error AlreadyClaimed();
    error NoPosition();

    constructor(address _accessControl, address _protocolSelector) {
        ACCESS_CONTROL = AccessControl(_accessControl);
        protocolSelector = _protocolSelector;
        feePercentage = DEFAULT_FEE;
        feeRecipient = msg.sender;
    }

    /**
     * @dev Create a new prediction market with its own vault
     */
    function createMarket(
        string calldata question,
        uint256 endTime,
        address token
    ) external returns (uint256 marketId) {
        ACCESS_CONTROL.assertOwner(msg.sender);
        require(endTime > block.timestamp, "Invalid end time");

        marketId = nextMarketId++;

        MarketVault vault = new MarketVault(
            IERC20(token),
            string(abi.encodePacked("Market ", _toString(marketId), " Vault")),
            string(abi.encodePacked("MKT", _toString(marketId))),
            address(this),
            protocolSelector
        );

        markets[marketId] = Market({
            id: marketId,
            question: question,
            endTime: endTime,
            token: token,
            vault: vault,
            totalYesShares: 0,
            totalNoShares: 0,
            resolved: false,
            outcome: false,
            status: MarketStatus.Active
        });

        emit MarketCreated(marketId, question, endTime, token, address(vault));
    }

    /**
     * @dev Place a bet on YES or NO
     * @param marketId Market ID
     * @param isYes true for YES, false for NO
     * @param amount Amount of collateral to bet
     */
    function placeBet(
        uint256 marketId,
        bool isYes,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        Market storage market = markets[marketId];
        require(market.id == marketId, "Market not found");
        require(block.timestamp < market.endTime, "Market ended");
        require(market.status == MarketStatus.Active, "Market not active");

        IERC20 token = IERC20(market.token);

        uint256 fee = (amount * feePercentage) / BASIS_POINTS;
        uint256 netAmount = amount - fee;

        token.safeTransferFrom(msg.sender, address(this), amount);

        if (fee > 0) {
            token.safeTransfer(feeRecipient, fee);
        }

        token.safeTransfer(address(market.vault), netAmount);

        uint256 shares = market.vault.depositForMarket(netAmount);

        Position storage position = positions[marketId][msg.sender];
        if (isYes) {
            position.yesShares += shares;
            market.totalYesShares += shares;
        } else {
            position.noShares += shares;
            market.totalNoShares += shares;
        }

        emit BetPlaced(marketId, msg.sender, isYes, amount, shares);
    }

    /**
     * @dev Resolve market with outcome
     */
    function resolveMarket(
        uint256 marketId,
        bool outcome
    ) external nonReentrant {
        ACCESS_CONTROL.assertOwner(msg.sender);

        Market storage market = markets[marketId];
        require(market.id == marketId, "Market not found");
        require(block.timestamp >= market.endTime, "Market not ended");
        require(!market.resolved, "Already resolved");

        market.resolved = true;
        market.outcome = outcome;
        market.status = MarketStatus.Resolved;

        emit MarketResolved(marketId, outcome);
    }

    /**
     * @dev Claim winnings after market resolves
     * Winners get: their stake + loser's stake + their yield
     * Losers get: their yield (they staked and earned yield, but lose principal)
     */
    function claimWinnings(uint256 marketId) external nonReentrant {
        Market storage market = markets[marketId];
        require(market.resolved, "Market not resolved");

        Position storage position = positions[marketId][msg.sender];
        require(!position.claimed, "Already claimed");
        require(position.yesShares > 0 || position.noShares > 0, "No position");

        uint256 winningShares = market.outcome
            ? position.yesShares
            : position.noShares;
        uint256 losingShares = market.outcome
            ? position.noShares
            : position.yesShares;

        position.claimed = true;

        uint256 totalPayout = 0;

        if (winningShares > 0) {
            uint256 totalWinningShares = market.outcome
                ? market.totalYesShares
                : market.totalNoShares;
            uint256 totalLosingShares = market.outcome
                ? market.totalNoShares
                : market.totalYesShares;

            uint256 baseAmount = market.vault.convertToAssets(winningShares);

            uint256 shareOfLosingPrincipal = 0;
            if (totalWinningShares > 0) {
                shareOfLosingPrincipal =
                    (totalLosingShares * winningShares) /
                    totalWinningShares;
            }

            totalPayout = baseAmount + shareOfLosingPrincipal;
        } else if (losingShares > 0) {
            uint256 currentValue = market.vault.convertToAssets(losingShares);

            if (currentValue > losingShares) {
                totalPayout = currentValue - losingShares;
            }
        }

        if (totalPayout > 0) {
            market.vault.withdrawForMarket(totalPayout, msg.sender);
        }

        emit WinningsClaimed(marketId, msg.sender, totalPayout);
    }

    /**
     * @dev Get user's potential payout (including current yield)
     */
    function getPotentialPayout(
        uint256 marketId,
        address user
    )
        external
        view
        returns (
            uint256 yesPayoutIfWin,
            uint256 noPayoutIfWin,
            uint256 currentYield
        )
    {
        Market storage market = markets[marketId];
        Position storage position = positions[marketId][user];

        if (position.yesShares == 0 && position.noShares == 0) {
            return (0, 0, 0);
        }

        currentYield = market.vault.getCurrentYield();

        if (position.yesShares > 0 && market.totalYesShares > 0) {
            uint256 baseYes = market.vault.convertToAssets(position.yesShares);
            uint256 losingPot = market.vault.convertToAssets(
                market.totalNoShares
            );
            uint256 yesShare = (losingPot * position.yesShares) /
                market.totalYesShares;
            yesPayoutIfWin = baseYes + yesShare;
        }

        if (position.noShares > 0 && market.totalNoShares > 0) {
            uint256 baseNo = market.vault.convertToAssets(position.noShares);
            uint256 losingPot = market.vault.convertToAssets(
                market.totalYesShares
            );
            uint256 noShare = (losingPot * position.noShares) /
                market.totalNoShares;
            noPayoutIfWin = baseNo + noShare;
        }
    }

    /**
     * @dev Get market info including yield
     */
    function getMarketInfo(
        uint256 marketId
    )
        external
        view
        returns (
            Market memory market,
            uint256 totalAssets,
            uint256 currentYield,
            uint256 yieldWithdrawn
        )
    {
        market = markets[marketId];
        if (address(market.vault) != address(0)) {
            (totalAssets, , currentYield, yieldWithdrawn, ) = market
                .vault
                .getVaultInfo();
        }
    }

    /**
     * @dev Update protocol selector
     */
    function setProtocolSelector(address newSelector) external {
        ACCESS_CONTROL.assertOwner(msg.sender);
        protocolSelector = newSelector;
    }

    /**
     * @dev Update fee
     */
    function setFeePercentage(uint256 newFee) external {
        ACCESS_CONTROL.assertOwner(msg.sender);
        require(newFee <= 1000, "Fee too high");
        feePercentage = newFee;
    }

    /**
     * @dev Helper to convert uint to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
