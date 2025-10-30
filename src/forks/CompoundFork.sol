// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";
import {USDC} from "../mocks/USDC.sol";

/**
 * @title CompoundFork
 * @dev Fork implementation of Compound protocol with complex yield calculation
 * This contract replicates the core functionality of the real Compound protocol
 */
contract CompoundFork is IYieldProtocol {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => mapping(address => uint256)) public userDepositTime;
    mapping(address => uint256) public totalDeposited;
    mapping(address => uint256) public accumulatedYield;
    mapping(address => uint256) public lastAccrualTime;

    uint256 public baseApy;
    uint256 public protocolFee;
    uint256 public lastUpdateTime;
    bool private initialized;
    address public owner;

    uint256 public constant BONUS_MULTIPLIER = 150;
    uint256 public constant MIN_STAKE_DURATION = 30 days;

    constructor() {
        owner = msg.sender;
        lastUpdateTime = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
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
        uint256 yieldAmount = (principal * baseApy * timeElapsed) / (365 days * 10000);

        if (yieldAmount > 0) {
            try USDC(tokenAddress).mint(address(this), yieldAmount) {
                accumulatedYield[tokenAddress] += yieldAmount;
            } catch {}
        }

        lastAccrualTime[tokenAddress] = block.timestamp;
    }

    /**
     * @dev Manually trigger yield accrual for a token
     */
    function accrueYield(address tokenAddress) external {
        _accrueYield(tokenAddress);
    }

    /**
     * @dev Initialize the protocol
     */
    function initialize(uint256 initialApy, uint256 _protocolFee) external override onlyOwner {
        require(!initialized, "Already initialized");
        baseApy = initialApy;
        protocolFee = _protocolFee;
        initialized = true;
    }

    /**
     * @dev Deposit tokens
     */
    function deposit(IERC20 token, uint256 amount) external override returns (bool success) {
        require(amount > 0, "Invalid amount");

        _accrueYield(address(token));

        token.safeTransferFrom(msg.sender, address(this), amount);

        userBalances[msg.sender][address(token)] += amount;
        userDepositTime[msg.sender][address(token)] = block.timestamp;
        totalDeposited[address(token)] += amount;

        emit Deposit(msg.sender, amount, amount);
        return true;
    }

    /**
     * @dev Withdraw tokens
     */
    function withdraw(IERC20 token, uint256 amount) external override returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");
        require(userBalances[msg.sender][address(token)] >= amount, "Insufficient balance");

        _accrueYield(address(token));

        uint256 stakeDuration = block.timestamp - userDepositTime[msg.sender][address(token)];
        uint256 yield = _calculateYield(amount, stakeDuration);

        amountReceived = amount + yield;

        uint256 availableBalance = token.balanceOf(address(this));
        if (amountReceived > availableBalance) {
            amountReceived = availableBalance;
        }

        userBalances[msg.sender][address(token)] -= amount;
        totalDeposited[address(token)] -= amount;

        if (amountReceived > 0) {
            token.safeTransfer(msg.sender, amountReceived);
        }

        emit Withdrawal(msg.sender, amount, amountReceived);
    }

    /**
     * @dev Get user's balance including accrued yield
     */
    function getBalance(address user, IERC20 token) external view override returns (uint256 balance) {
        uint256 principal = userBalances[user][address(token)];
        if (principal > 0) {
            uint256 stakeDuration = block.timestamp - userDepositTime[user][address(token)];
            uint256 yield = _calculateYield(principal, stakeDuration);
            balance = principal + yield;
        }
    }

    /**
     * @dev Get user's shares (for Compound, shares = principal)
     */
    function getShares(address user, IERC20 token) external view override returns (uint256 shares) {
        shares = userBalances[user][address(token)];
    }

    /**
     * @dev Get current APY (dynamic based on TVL)
     */
    function getCurrentApy() external view override returns (uint256 apy) {
        uint256 totalTvl = address(this).balance;
        if (totalTvl > 1000 ether) {
            apy = baseApy + 200;
        } else if (totalTvl > 100 ether) {
            apy = baseApy + 100;
        } else {
            apy = baseApy;
        }
    }

    /**
     * @dev Get protocol name
     */
    function getProtocolName() external pure override returns (string memory name) {
        name = "Compound Fork";
    }

    /**
     * @dev Get total value locked
     */
    function getTotalTvl(IERC20 token) external view override returns (uint256 tvl) {
        tvl = token.balanceOf(address(this));
    }

    /**
     * @dev Get exchange rate (varies based on accumulated yield)
     */
    function getExchangeRate(IERC20 token) external view override returns (uint256 rate) {
        uint256 totalSupply = totalDeposited[address(token)];
        uint256 totalAssets = token.balanceOf(address(this));

        if (totalSupply == 0) {
            rate = 1e18;
        } else {
            rate = (totalAssets * 1e18) / totalSupply;
        }
    }

    /**
     * @dev Check if user is whitelisted (always true for Compound)
     */
    function isWhitelisted(address) external pure override returns (bool) {
        return true;
    }

    /**
     * @dev Calculate yield based on amount and duration
     */
    function _calculateYield(uint256 amount, uint256 duration) internal view returns (uint256 yield) {
        uint256 annualYield = (amount * baseApy) / 10000;
        yield = (annualYield * duration) / 365 days;

        if (duration >= MIN_STAKE_DURATION) {
            yield = (yield * BONUS_MULTIPLIER) / 100;
        }
    }

    /**
     * @dev Update base APY (for testing purposes)
     */
    function setBaseApy(uint256 newApy) external onlyOwner {
        baseApy = newApy;
    }

    /**
     * @dev Add yield to the protocol (simulates external yield generation)
     */
    function addYield(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        accumulatedYield[address(token)] += amount;
    }
}
