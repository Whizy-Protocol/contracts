// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";
import {USDC} from "../mocks/USDC.sol";

/**
 * @title MorphoFork
 * @dev Fork implementation of Morpho protocol with whitelisting features
 * This contract replicates the core functionality of the real Morpho protocol
 */
contract MorphoFork is IYieldProtocol {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => uint256) public totalDeposited;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public lastAccrualTime;

    uint256 public currentApy;
    uint256 public protocolFee;
    bool private initialized;
    address public owner;

    event UserWhitelisted(address indexed user);
    event UserRemovedFromWhitelist(address indexed user);

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Accrue yield by minting new USDC tokens if using mock USDC
     * This simulates yield generation for testing purposes
     */
    function _accrueYield(address tokenAddress) internal {
        if (lastAccrualTime[tokenAddress] == 0) {
            lastAccrualTime[tokenAddress] = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastAccrualTime[tokenAddress];
        if (timeElapsed == 0 || totalDeposited[tokenAddress] == 0) {
            return;
        }

        uint256 principal = totalDeposited[tokenAddress];
        uint256 yieldAmount = (principal * currentApy * timeElapsed) / (365 days * 10000);

        if (yieldAmount > 0) {
            try USDC(tokenAddress).mint(address(this), yieldAmount) {} catch {}
        }

        lastAccrualTime[tokenAddress] = block.timestamp;
    }

    /**
     * @dev Manually trigger yield accrual for a token
     */
    function accrueYield(address tokenAddress) external {
        _accrueYield(tokenAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Not whitelisted");
        _;
    }

    /**
     * @dev Initialize the protocol
     */
    function initialize(uint256 initialApy, uint256 _protocolFee) external override onlyOwner {
        require(!initialized, "Already initialized");
        currentApy = initialApy;
        protocolFee = _protocolFee;
        initialized = true;
    }

    /**
     * @dev Deposit tokens (only whitelisted users)
     */
    function deposit(IERC20 token, uint256 amount) external override onlyWhitelisted returns (bool success) {
        require(amount > 0, "Invalid amount");

        _accrueYield(address(token));

        token.safeTransferFrom(msg.sender, address(this), amount);

        userBalances[msg.sender][address(token)] += amount;
        totalDeposited[address(token)] += amount;

        emit Deposit(msg.sender, amount, amount);
        return true;
    }

    /**
     * @dev Withdraw tokens (only whitelisted users)
     */
    function withdraw(IERC20 token, uint256 amount) external override onlyWhitelisted returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");
        require(userBalances[msg.sender][address(token)] >= amount, "Insufficient balance");

        _accrueYield(address(token));

        uint256 userBalance = userBalances[msg.sender][address(token)];
        uint256 totalBalance = token.balanceOf(address(this));
        uint256 totalTracked = totalDeposited[address(token)];

        if (amount >= userBalance) {
            if (totalTracked > 0) {
                amountReceived = (userBalance * totalBalance) / totalTracked;
            } else {
                amountReceived = amount;
            }
            userBalances[msg.sender][address(token)] = 0;
        } else {
            if (totalTracked > 0) {
                amountReceived = (amount * totalBalance) / totalTracked;
            } else {
                amountReceived = amount;
            }
            userBalances[msg.sender][address(token)] -= amount;
        }

        totalDeposited[address(token)] -= amount;

        if (amountReceived > 0) {
            token.safeTransfer(msg.sender, amountReceived);
        }

        emit Withdrawal(msg.sender, amount, amountReceived);
    }

    /**
     * @dev Get user's balance (proportional share of total balance including yield)
     */
    function getBalance(address user, IERC20 token) external view override returns (uint256 balance) {
        uint256 userTracked = userBalances[user][address(token)];
        if (userTracked == 0) return 0;

        uint256 totalBalance = token.balanceOf(address(this));
        uint256 totalTracked = totalDeposited[address(token)];

        if (totalTracked > 0) {
            balance = (userTracked * totalBalance) / totalTracked;
        } else {
            balance = userTracked;
        }
    }

    /**
     * @dev Get user's shares (same as balance for Morpho)
     */
    function getShares(address user, IERC20 token) external view override returns (uint256 shares) {
        shares = userBalances[user][address(token)];
    }

    /**
     * @dev Get current APY
     */
    function getCurrentApy() external view override returns (uint256 apy) {
        apy = currentApy;
    }

    /**
     * @dev Get protocol name
     */
    function getProtocolName() external pure override returns (string memory name) {
        name = "Morpho Fork";
    }

    /**
     * @dev Get total value locked
     */
    function getTotalTvl(IERC20 token) external view override returns (uint256 tvl) {
        tvl = token.balanceOf(address(this));
    }

    /**
     * @dev Get exchange rate (1:1 for Morpho)
     */
    function getExchangeRate(IERC20) external pure override returns (uint256 rate) {
        rate = 1e18;
    }

    /**
     * @dev Check if user is whitelisted
     */
    function isWhitelisted(address user) external view override returns (bool) {
        return whitelist[user];
    }

    /**
     * @dev Add user to whitelist
     */
    function addToWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
        emit UserWhitelisted(user);
    }

    /**
     * @dev Remove user from whitelist
     */
    function removeFromWhitelist(address user) external onlyOwner {
        whitelist[user] = false;
        emit UserRemovedFromWhitelist(user);
    }

    /**
     * @dev Update APY (for testing purposes)
     */
    function setCurrentApy(uint256 newApy) external onlyOwner {
        currentApy = newApy;
    }
}
