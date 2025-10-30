// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";
import {AaveFork} from "../forks/AaveFork.sol";

/**
 * @title AaveAdapter
 * @dev Adapter contract for integrating with Aave protocol
 * This adapter provides a standardized interface for the prediction market
 * to interact with Aave's liquid staking functionality
 */
contract AaveAdapter is IYieldProtocol {
    using SafeERC20 for IERC20;

    AaveFork public immutable AAVE_FORK;
    address public owner;
    bool private initialized;

    event AdapterInitialized(address indexed fork, address indexed owner);
    event DepositRouted(address indexed user, address indexed token, uint256 amount);
    event WithdrawalRouted(address indexed user, address indexed token, uint256 amount);

    constructor(address _aaveFork) {
        AAVE_FORK = AaveFork(_aaveFork);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @dev Initialize the adapter
     */
    function initialize(uint256 initialApy, uint256 protocolFee) external override onlyOwner {
        require(!initialized, "Already initialized");

        AAVE_FORK.initialize(initialApy, protocolFee);
        initialized = true;
        emit AdapterInitialized(address(AAVE_FORK), owner);
    }

    /**
     * @dev Route deposit to Aave fork
     */
    function deposit(IERC20 token, uint256 amount) external override returns (bool success) {
        require(amount > 0, "Invalid amount");

        token.safeTransferFrom(msg.sender, address(this), amount);

        token.safeIncreaseAllowance(address(AAVE_FORK), amount);

        success = AAVE_FORK.deposit(token, amount);

        if (success) {
            emit DepositRouted(msg.sender, address(token), amount);
            emit Deposit(msg.sender, amount, amount);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @dev Route withdrawal from Aave fork
     */
    function withdraw(IERC20 token, uint256 amount) external override returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");

        amountReceived = AAVE_FORK.withdraw(token, amount);

        if (amountReceived > 0) {
            token.safeTransfer(msg.sender, amountReceived);
            emit WithdrawalRouted(msg.sender, address(token), amountReceived);
            emit Withdrawal(msg.sender, amount, amountReceived);
        }
    }

    /**
     * @dev Get user's balance from the fork
     */
    function getBalance(address user, IERC20 token) external view override returns (uint256 balance) {
        balance = AAVE_FORK.getBalance(user, token);
    }

    /**
     * @dev Get user's shares from the fork
     */
    function getShares(address user, IERC20 token) external view override returns (uint256 shares) {
        shares = AAVE_FORK.getShares(user, token);
    }

    /**
     * @dev Get current APY from the fork
     */
    function getCurrentApy() external view override returns (uint256 apy) {
        apy = AAVE_FORK.getCurrentApy();
    }

    /**
     * @dev Get protocol name with adapter suffix
     */
    function getProtocolName() external pure override returns (string memory name) {
        name = "Aave Adapter";
    }

    /**
     * @dev Get total value locked in the fork
     */
    function getTotalTvl(IERC20 token) external view override returns (uint256 tvl) {
        tvl = AAVE_FORK.getTotalTvl(token);
    }

    /**
     * @dev Get exchange rate from the fork
     */
    function getExchangeRate(IERC20 token) external view override returns (uint256 rate) {
        rate = AAVE_FORK.getExchangeRate(token);
    }

    /**
     * @dev Check if user is whitelisted (delegates to fork)
     */
    function isWhitelisted(address user) external view override returns (bool) {
        return AAVE_FORK.isWhitelisted(user);
    }

    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyWithdraw(IERC20 token) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(owner, balance);
        }
    }

    /**
     * @dev Update owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}
