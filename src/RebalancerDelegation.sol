// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ProtocolSelector} from "./ProtocolSelector.sol";

/**
 * @title RebalancerDelegation
 * @notice Allows users to delegate auto-rebalancing to backend operators
 *
 * Flow:
 * 1. User deposits USDC + enables auto-rebalance
 * 2. Rebalancer can rebalance on user's behalf
 * 3. User can withdraw anytime
 */
contract RebalancerDelegation {
    using SafeERC20 for IERC20;

    ProtocolSelector public immutable PROTOCOL_SELECTOR;
    IERC20 public immutable USDC;

    mapping(address => bool) public operators;
    address public owner;

    struct UserConfig {
        bool autoRebalanceEnabled;
        uint8 riskProfile;
        uint256 depositedAmount;
    }

    mapping(address => UserConfig) public userConfigs;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event AutoRebalanceEnabled(address indexed user, uint8 riskProfile);
    event AutoRebalanceDisabled(address indexed user);
    event Rebalanced(
        address indexed user,
        address indexed operator,
        uint256 amount
    );
    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);

    error NotOperator();
    error NotOwner();
    error AutoRebalanceNotEnabled();
    error InsufficientBalance();

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert NotOperator();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _protocolSelector, address _usdc) {
        PROTOCOL_SELECTOR = ProtocolSelector(_protocolSelector);
        USDC = IERC20(_usdc);
        owner = msg.sender;
        operators[msg.sender] = true;
    }

    /**
     * @notice User deposits USDC and enables auto-rebalancing
     * @param amount Amount of USDC to deposit
     * @param riskProfile Risk level (1=low, 2=medium, 3=high)
     */
    function depositAndEnable(uint256 amount, uint8 riskProfile) external {
        require(amount > 0, "Amount must be > 0");
        require(riskProfile >= 1 && riskProfile <= 3, "Invalid risk profile");

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        userConfigs[msg.sender].autoRebalanceEnabled = true;
        userConfigs[msg.sender].riskProfile = riskProfile;
        userConfigs[msg.sender].depositedAmount += amount;

        USDC.safeIncreaseAllowance(address(PROTOCOL_SELECTOR), amount);

        PROTOCOL_SELECTOR.autoDeposit(USDC, amount);

        emit Deposited(msg.sender, amount);
        emit AutoRebalanceEnabled(msg.sender, riskProfile);
    }

    /**
     * @notice Backend operator rebalances user's funds
     * @param user User to rebalance
     */
    function rebalance(address user) external onlyOperator {
        UserConfig memory config = userConfigs[user];
        if (!config.autoRebalanceEnabled) revert AutoRebalanceNotEnabled();

        uint256 currentBalance = PROTOCOL_SELECTOR.getTotalBalance(
            address(this),
            USDC
        );

        if (currentBalance == 0) return;

        uint256 withdrawn = PROTOCOL_SELECTOR.autoWithdraw(
            USDC,
            currentBalance
        );

        USDC.safeIncreaseAllowance(address(PROTOCOL_SELECTOR), withdrawn);
        PROTOCOL_SELECTOR.autoDeposit(USDC, withdrawn);

        emit Rebalanced(user, msg.sender, withdrawn);
    }

    /**
     * @notice User withdraws their funds
     * @param amount Amount to withdraw (0 = withdraw all)
     */
    function withdraw(uint256 amount) external {
        UserConfig storage config = userConfigs[msg.sender];

        uint256 toWithdraw = amount;
        if (amount == 0) {
            toWithdraw = PROTOCOL_SELECTOR.getTotalBalance(address(this), USDC);
        }

        if (toWithdraw == 0) revert InsufficientBalance();

        uint256 received = PROTOCOL_SELECTOR.autoWithdraw(USDC, toWithdraw);

        USDC.safeTransfer(msg.sender, received);

        if (received >= config.depositedAmount) {
            config.depositedAmount = 0;
        } else {
            config.depositedAmount -= received;
        }

        emit Withdrawn(msg.sender, received);
    }

    /**
     * @notice User disables auto-rebalancing (but keeps funds deposited)
     */
    function disableAutoRebalance() external {
        userConfigs[msg.sender].autoRebalanceEnabled = false;
        emit AutoRebalanceDisabled(msg.sender);
    }

    /**
     * @notice User enables auto-rebalancing
     */
    function enableAutoRebalance(uint8 riskProfile) external {
        require(riskProfile >= 1 && riskProfile <= 3, "Invalid risk profile");
        userConfigs[msg.sender].autoRebalanceEnabled = true;
        userConfigs[msg.sender].riskProfile = riskProfile;
        emit AutoRebalanceEnabled(msg.sender, riskProfile);
    }

    /**
     * @notice Get user's current balance (including yield)
     */
    function getUserBalance(address user) external view returns (uint256) {
        return PROTOCOL_SELECTOR.getTotalBalance(address(this), USDC);
    }

    function addOperator(address operator) external onlyOwner {
        operators[operator] = true;
        emit OperatorAdded(operator);
    }

    function removeOperator(address operator) external onlyOwner {
        operators[operator] = false;
        emit OperatorRemoved(operator);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}
