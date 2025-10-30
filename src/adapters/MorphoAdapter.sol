// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";
import {MorphoFork} from "../forks/MorphoFork.sol";

/**
 * @title MorphoAdapter
 * @dev Adapter contract for integrating with Morpho protocol
 * This adapter handles whitelisting and provides a standardized interface
 * for the prediction market to interact with Morpho's yield features
 */
contract MorphoAdapter is IYieldProtocol {
    using SafeERC20 for IERC20;

    MorphoFork public immutable MORPHO_FORK;
    address public owner;
    bool private initialized;
    mapping(address => bool) public authorizedCallers;

    event AdapterInitialized(address indexed fork, address indexed owner);
    event CallerAuthorized(address indexed caller);
    event CallerRevoked(address indexed caller);
    event DepositRouted(address indexed user, address indexed token, uint256 amount);
    event WithdrawalRouted(address indexed user, address indexed token, uint256 amount);

    constructor(address _morphoFork) {
        MORPHO_FORK = MorphoFork(_morphoFork);
        owner = msg.sender;
        authorizedCallers[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender], "Not authorized");
        _;
    }

    /**
     * @dev Initialize the adapter
     */
    function initialize(uint256 initialApy, uint256 protocolFee) external override onlyOwner {
        require(!initialized, "Already initialized");

        MORPHO_FORK.initialize(initialApy, protocolFee);
        initialized = true;
        emit AdapterInitialized(address(MORPHO_FORK), owner);
    }

    /**
     * @dev Route deposit to Morpho fork (with whitelisting check)
     */
    function deposit(IERC20 token, uint256 amount) external override onlyAuthorized returns (bool success) {
        require(amount > 0, "Invalid amount");

        if (!MORPHO_FORK.isWhitelisted(address(this))) {
            return false;
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        token.safeIncreaseAllowance(address(MORPHO_FORK), amount);

        success = MORPHO_FORK.deposit(token, amount);

        if (success) {
            emit DepositRouted(msg.sender, address(token), amount);
            emit Deposit(msg.sender, amount, amount);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @dev Route withdrawal from Morpho fork
     */
    function withdraw(IERC20 token, uint256 amount) external override onlyAuthorized returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");

        amountReceived = MORPHO_FORK.withdraw(token, amount);

        if (amountReceived > 0) {
            token.safeTransfer(msg.sender, amountReceived);
            emit WithdrawalRouted(msg.sender, address(token), amountReceived);
            emit Withdrawal(msg.sender, amount, amountReceived);
        }
    }

    /**
     * @dev Get user's balance from the fork
     * When queried for the adapter itself, return the adapter's balance in the fork
     */
    function getBalance(address user, IERC20 token) external view override returns (uint256 balance) {
        if (user == address(this)) {
            balance = MORPHO_FORK.getBalance(address(this), token);
        } else {
            balance = MORPHO_FORK.getBalance(user, token);
        }
    }

    /**
     * @dev Get user's shares from the fork
     * When queried for the adapter itself, return the adapter's shares in the fork
     */
    function getShares(address user, IERC20 token) external view override returns (uint256 shares) {
        if (user == address(this)) {
            shares = MORPHO_FORK.getShares(address(this), token);
        } else {
            shares = MORPHO_FORK.getShares(user, token);
        }
    }

    /**
     * @dev Get current APY from the fork
     */
    function getCurrentApy() external view override returns (uint256 apy) {
        apy = MORPHO_FORK.getCurrentApy();
    }

    /**
     * @dev Get protocol name with adapter suffix
     */
    function getProtocolName() external pure override returns (string memory name) {
        name = "Morpho Adapter";
    }

    /**
     * @dev Get total value locked in the fork
     */
    function getTotalTvl(IERC20 token) external view override returns (uint256 tvl) {
        tvl = MORPHO_FORK.getTotalTvl(token);
    }

    /**
     * @dev Get exchange rate from the fork
     */
    function getExchangeRate(IERC20 token) external view override returns (uint256 rate) {
        rate = MORPHO_FORK.getExchangeRate(token);
    }

    /**
     * @dev Check if user is whitelisted through this adapter
     */
    function isWhitelisted(address user) external view override returns (bool) {
        return authorizedCallers[user] && MORPHO_FORK.isWhitelisted(address(this));
    }

    /**
     * @dev Authorize a caller to use this adapter
     */
    function authorizeCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
        emit CallerAuthorized(caller);
    }

    /**
     * @dev Revoke authorization for a caller
     */
    function revokeCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit CallerRevoked(caller);
    }

    /**
     * @dev Request whitelisting from the fork (owner function)
     */
    function requestWhitelist() external onlyOwner {}

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
        authorizedCallers[newOwner] = true;
        authorizedCallers[msg.sender] = false;
    }
}
