// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {IYieldProtocol} from "./interfaces/IYieldProtocol.sol";

/**
 * @title ProtocolSelector
 * @dev Contract for selecting and managing yield protocols
 */
contract ProtocolSelector is AccessControl {
    using SafeERC20 for IERC20;

    uint8 public constant PROTOCOL_AAVE = 1;
    uint8 public constant PROTOCOL_MORPHO = 2;
    uint8 public constant PROTOCOL_COMPOUND = 3;

    event ProtocolRegistered(uint8 indexed protocolType, address indexed protocolAddress, string name, uint8 riskLevel);
    event ProtocolUpdated(address indexed protocolAddress, uint256 newApy, uint256 newTvl);
    event AutoDepositExecuted(address indexed user, address indexed protocol, uint256 amount, bool success);
    event AutoWithdrawExecuted(address indexed user, address indexed protocol, uint256 amount, bool success);

    struct ProtocolInfo {
        uint8 protocolType;
        address protocolAddress;
        uint256 currentApy;
        string name;
        uint256 tvl;
        uint8 riskLevel;
        bool active;
    }

    struct SelectionResult {
        ProtocolInfo selectedProtocol;
        string reason;
        ProtocolInfo[] alternativeProtocols;
    }

    ProtocolInfo[] public availableProtocols;
    mapping(uint8 => address) public protocolTypeToAddress;
    bool public autoSelectionEnabled;
    uint256 public minApyThreshold;
    uint8 public maxRiskTolerance;

    mapping(address => mapping(IERC20 => uint256)) public userDeposits;

    error NoProtocolsAvailable();
    error ProtocolNotFound();
    error InvalidProtocolType();
    error DepositFailed();
    error WithdrawFailed();
    error InsufficientBalance();

    /**
     * @dev Constructor
     * @param _minApyThreshold Minimum APY threshold in basis points
     * @param _maxRiskTolerance Maximum risk tolerance (1-10)
     */
    constructor(uint256 _minApyThreshold, uint8 _maxRiskTolerance) {
        autoSelectionEnabled = true;
        minApyThreshold = _minApyThreshold;
        maxRiskTolerance = _maxRiskTolerance;
    }

    /**
     * @dev Register a new protocol
     * @param protocolType Type of protocol (1=Aave, 2=Morpho, 3=Compound)
     * @param protocolAddress Address of the protocol contract
     * @param riskLevel Risk level (1=lowest, 10=highest)
     */
    function registerProtocol(uint8 protocolType, address protocolAddress, uint8 riskLevel) external onlyOwner {
        require(protocolAddress != address(0), "Invalid protocol address");
        require(protocolType >= 1 && protocolType <= 3, "Invalid protocol type");
        require(riskLevel >= 1 && riskLevel <= 10, "Invalid risk level");

        IYieldProtocol protocol = IYieldProtocol(protocolAddress);

        ProtocolInfo memory protocolInfo = ProtocolInfo({
            protocolType: protocolType,
            protocolAddress: protocolAddress,
            currentApy: protocol.getCurrentApy(),
            name: protocol.getProtocolName(),
            tvl: 0,
            riskLevel: riskLevel,
            active: true
        });

        availableProtocols.push(protocolInfo);
        protocolTypeToAddress[protocolType] = protocolAddress;

        emit ProtocolRegistered(protocolType, protocolAddress, protocolInfo.name, riskLevel);
    }

    /**
     * @dev Select the best protocol based on APY, risk, and TVL
     * Formula: Score = (APY × 0.5) + (TVL_normalized × 0.3) - (Risk_level × 0.2)
     * @return bestProtocol The selected protocol info
     */
    function selectBestProtocol(
        IERC20 /* token */
    )
        external
        view
        returns (ProtocolInfo memory bestProtocol)
    {
        if (availableProtocols.length == 0) revert NoProtocolsAvailable();

        int256 bestScore = type(int256).min;
        bool found = false;
        uint256 maxTvl = 0;

        for (uint256 i = 0; i < availableProtocols.length; i++) {
            if (availableProtocols[i].active && availableProtocols[i].tvl > maxTvl) {
                maxTvl = availableProtocols[i].tvl;
            }
        }

        if (maxTvl == 0) maxTvl = 1;

        for (uint256 i = 0; i < availableProtocols.length; i++) {
            ProtocolInfo memory protocol = availableProtocols[i];

            if (!protocol.active) continue;
            if (protocol.currentApy < minApyThreshold) continue;
            if (protocol.riskLevel > maxRiskTolerance) continue;

            int256 apyComponent = int256(protocol.currentApy * 50);

            int256 tvlNormalized = int256((protocol.tvl * 30) / maxTvl);

            int256 riskComponent = int256(uint256(protocol.riskLevel) * 20);

            int256 score = apyComponent + tvlNormalized - riskComponent;

            if (!found || score > bestScore) {
                bestScore = score;
                bestProtocol = protocol;
                found = true;
            }
        }

        if (!found) revert NoProtocolsAvailable();
    }

    /**
     * @dev Auto deposit tokens into the best protocol
     * @param token The ERC20 token to deposit
     * @param amount Amount to deposit
     * @return success True if deposit was successful
     * @return reason Reason for success/failure
     */
    function autoDeposit(IERC20 token, uint256 amount) external returns (bool success, string memory reason) {
        require(amount > 0, "Invalid amount");

        ProtocolInfo memory bestProtocol = this.selectBestProtocol(token);

        token.safeTransferFrom(msg.sender, address(this), amount);

        token.safeIncreaseAllowance(bestProtocol.protocolAddress, amount);

        try IYieldProtocol(bestProtocol.protocolAddress).deposit(token, amount) returns (bool depositSuccess) {
            success = depositSuccess;
            if (depositSuccess) {
                userDeposits[msg.sender][token] += amount;
                reason = "Successfully deposited to highest APY protocol";
            } else {
                token.safeTransfer(msg.sender, amount);
                reason = "Deposit failed";
            }
        } catch {
            token.safeTransfer(msg.sender, amount);
            success = false;
            reason = "Protocol deposit reverted";
        }

        emit AutoDepositExecuted(msg.sender, bestProtocol.protocolAddress, amount, success);
    }

    /**
     * @dev Auto withdraw tokens from protocols
     * @param token The ERC20 token to withdraw
     * @param amount Amount to withdraw
     * @return amountReceived Amount actually received
     */
    function autoWithdraw(IERC20 token, uint256 amount) external returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");

        uint256 balanceBefore = token.balanceOf(address(this));

        for (uint256 i = 0; i < availableProtocols.length && amountReceived < amount; i++) {
            ProtocolInfo memory protocol = availableProtocols[i];

            if (!protocol.active) continue;

            IYieldProtocol protocolContract = IYieldProtocol(protocol.protocolAddress);

            uint256 protocolBalance = protocolContract.getBalance(address(protocolContract), token);

            if (protocolBalance == 0) {
                protocolBalance = protocolContract.getBalance(address(this), token);
            }

            if (protocolBalance == 0) continue;

            uint256 toWithdraw = amount - amountReceived;
            if (toWithdraw > protocolBalance) {
                toWithdraw = protocolBalance;
            }

            uint256 totalSharesAvailable = protocolContract.getShares(address(protocolContract), token);

            if (totalSharesAvailable == 0) {
                totalSharesAvailable = protocolContract.getShares(address(this), token);
            }

            if (totalSharesAvailable == 0) continue;

            uint256 sharesToWithdraw;

            if (toWithdraw >= protocolBalance * 95 / 100) {
                sharesToWithdraw = totalSharesAvailable;
            } else if (totalSharesAvailable > toWithdraw) {
                sharesToWithdraw = toWithdraw;
            } else {
                sharesToWithdraw = totalSharesAvailable;
            }

            try protocolContract.withdraw(token, sharesToWithdraw) returns (uint256 received) {
                amountReceived += received;
                emit AutoWithdrawExecuted(msg.sender, protocol.protocolAddress, received, true);
            } catch {
                emit AutoWithdrawExecuted(msg.sender, protocol.protocolAddress, 0, false);
            }
        }

        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 actualReceived = balanceAfter - balanceBefore;

        if (actualReceived == 0) revert InsufficientBalance();

        uint256 toDeduct =
            actualReceived > userDeposits[msg.sender][token] ? userDeposits[msg.sender][token] : actualReceived;
        userDeposits[msg.sender][token] -= toDeduct;
        token.safeTransfer(msg.sender, actualReceived);

        return actualReceived;
    }

    /**
     * @dev Get total balance across all protocols for a user
     * @param user Address of the user
     * @param token The ERC20 token
     * @return totalBalance Total balance across all protocols
     */
    function getTotalBalance(address user, IERC20 token) external view returns (uint256 totalBalance) {
        if (user == address(this)) {
            for (uint256 i = 0; i < availableProtocols.length; i++) {
                ProtocolInfo memory protocol = availableProtocols[i];

                if (!protocol.active) continue;

                IYieldProtocol protocolContract = IYieldProtocol(protocol.protocolAddress);

                uint256 balance = protocolContract.getBalance(protocol.protocolAddress, token);
                totalBalance += balance;
            }
        } else {
            for (uint256 i = 0; i < availableProtocols.length; i++) {
                ProtocolInfo memory protocol = availableProtocols[i];

                if (!protocol.active) continue;

                IYieldProtocol protocolContract = IYieldProtocol(protocol.protocolAddress);
                uint256 balance = protocolContract.getBalance(user, token);
                totalBalance += balance;
            }
        }
    }

    /**
     * @dev Get user's tracked deposit amount (principal only, not including yield)
     * @param user Address of the user (typically a market contract)
     * @param token The ERC20 token
     * @return deposit Amount user has deposited
     */
    function getUserDeposit(address user, IERC20 token) external view returns (uint256 deposit) {
        deposit = userDeposits[user][token];
    }

    /**
     * @dev Update protocol information
     * @param protocolAddress Address of the protocol
     */
    function updateProtocol(address protocolAddress) external onlyOwner {
        bool found = false;
        for (uint256 i = 0; i < availableProtocols.length; i++) {
            if (availableProtocols[i].protocolAddress == protocolAddress) {
                IYieldProtocol protocol = IYieldProtocol(protocolAddress);
                availableProtocols[i].currentApy = protocol.getCurrentApy();
                found = true;

                emit ProtocolUpdated(protocolAddress, availableProtocols[i].currentApy, availableProtocols[i].tvl);
                break;
            }
        }

        if (!found) revert ProtocolNotFound();
    }

    /**
     * @dev Update protocol information (alias for updateProtocol)
     * @param protocolAddress Address of the protocol
     */
    function updateProtocolInfo(
        address protocolAddress,
        IERC20 /* token */
    )
        external
        onlyOwner
    {
        bool found = false;
        for (uint256 i = 0; i < availableProtocols.length; i++) {
            if (availableProtocols[i].protocolAddress == protocolAddress) {
                IYieldProtocol protocol = IYieldProtocol(protocolAddress);
                availableProtocols[i].currentApy = protocol.getCurrentApy();
                found = true;

                emit ProtocolUpdated(protocolAddress, availableProtocols[i].currentApy, availableProtocols[i].tvl);
                break;
            }
        }

        if (!found) revert ProtocolNotFound();
    }

    /**
     * @dev Set protocol active status
     * @param protocolAddress Address of the protocol
     * @param active New active status
     */
    function setProtocolActive(address protocolAddress, bool active) external onlyOwner {
        bool found = false;
        for (uint256 i = 0; i < availableProtocols.length; i++) {
            if (availableProtocols[i].protocolAddress == protocolAddress) {
                availableProtocols[i].active = active;
                found = true;
                break;
            }
        }

        if (!found) revert ProtocolNotFound();
    }

    /**
     * @dev Enable or disable auto selection
     * @param enabled New auto selection status
     */
    function setAutoSelectionEnabled(bool enabled) external onlyOwner {
        autoSelectionEnabled = enabled;
    }

    /**
     * @dev Update minimum APY threshold
     * @param newThreshold New minimum APY threshold
     */
    function setMinApyThreshold(uint256 newThreshold) external onlyOwner {
        minApyThreshold = newThreshold;
    }

    /**
     * @dev Update maximum risk tolerance
     * @param newTolerance New maximum risk tolerance
     */
    function setMaxRiskTolerance(uint8 newTolerance) external onlyOwner {
        require(newTolerance >= 1 && newTolerance <= 10, "Invalid tolerance");
        maxRiskTolerance = newTolerance;
    }

    /**
     * @dev Get all available protocols
     * @return protocols Array of all protocols
     */
    function getAvailableProtocols() external view returns (ProtocolInfo[] memory protocols) {
        protocols = availableProtocols;
    }

    /**
     * @dev Get all available protocols (alias)
     * @return protocols Array of all protocols
     */
    function getAllProtocols() external view returns (ProtocolInfo[] memory protocols) {
        protocols = availableProtocols;
    }

    /**
     * @dev Get protocol by type
     * @param protocolType Type of protocol
     * @return protocol Protocol information
     */
    function getProtocolByType(uint8 protocolType) external view returns (ProtocolInfo memory protocol) {
        address protocolAddress = protocolTypeToAddress[protocolType];
        if (protocolAddress == address(0)) revert ProtocolNotFound();

        for (uint256 i = 0; i < availableProtocols.length; i++) {
            if (availableProtocols[i].protocolAddress == protocolAddress) {
                return availableProtocols[i];
            }
        }

        revert ProtocolNotFound();
    }

    /**
     * @dev Get current best APY across all protocols
     * @return bestApy The highest APY available
     */
    function getCurrentBestApy() external view returns (uint256 bestApy) {
        for (uint256 i = 0; i < availableProtocols.length; i++) {
            if (availableProtocols[i].active && availableProtocols[i].currentApy > bestApy) {
                bestApy = availableProtocols[i].currentApy;
            }
        }
    }
}
