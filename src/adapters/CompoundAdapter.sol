// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";
import {CompoundFork} from "../forks/CompoundFork.sol";

/**
 * @title CompoundAdapter
 * @dev Adapter contract for integrating with Compound protocol
 * This adapter handles time-based yield calculations and provides a standardized interface
 * for the prediction market to interact with Compound's complex yield features
 */
contract CompoundAdapter is IYieldProtocol {
    using SafeERC20 for IERC20;

    CompoundFork public immutable COMPOUND_FORK;
    address public owner;
    bool private initialized;

    mapping(address => mapping(address => uint256)) public userFirstDepositTime;
    mapping(address => uint256) public totalStakeTime;

    event AdapterInitialized(address indexed fork, address indexed owner);
    event DepositRouted(address indexed user, address indexed token, uint256 amount);
    event WithdrawalRouted(address indexed user, address indexed token, uint256 amount);
    event BonusYieldEarned(address indexed user, uint256 bonusAmount);
    event StakeTimeUpdated(address indexed user, uint256 totalTime);

    constructor(address _compoundFork) {
        COMPOUND_FORK = CompoundFork(_compoundFork);
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

        COMPOUND_FORK.initialize(initialApy, protocolFee);
        initialized = true;
        emit AdapterInitialized(address(COMPOUND_FORK), owner);
    }

    /**
     * @dev Route deposit to Compound fork with time tracking
     */
    function deposit(IERC20 token, uint256 amount) external override returns (bool success) {
        require(amount > 0, "Invalid amount");

        if (userFirstDepositTime[msg.sender][address(token)] == 0) {
            userFirstDepositTime[msg.sender][address(token)] = block.timestamp;
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        token.safeIncreaseAllowance(address(COMPOUND_FORK), amount);

        success = COMPOUND_FORK.deposit(token, amount);

        if (success) {
            emit DepositRouted(msg.sender, address(token), amount);
            emit Deposit(msg.sender, amount, amount);
            _updateStakeTime(msg.sender);
        } else {
            token.safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @dev Route withdrawal from Compound fork with bonus calculations
     */
    function withdraw(IERC20 token, uint256 amount) external override returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");

        uint256 bonusYield = _calculateBonusYield(msg.sender, address(token), amount);

        amountReceived = COMPOUND_FORK.withdraw(token, amount);

        if (bonusYield > 0 && token.balanceOf(address(this)) >= bonusYield) {
            amountReceived += bonusYield;
            emit BonusYieldEarned(msg.sender, bonusYield);
        }

        if (amountReceived > 0) {
            token.safeTransfer(msg.sender, amountReceived);
            emit WithdrawalRouted(msg.sender, address(token), amountReceived);
            emit Withdrawal(msg.sender, amount, amountReceived);
        }

        _updateStakeTime(msg.sender);
    }

    /**
     * @dev Get user's balance from the fork with bonus calculations
     */
    function getBalance(address user, IERC20 token) external view override returns (uint256 balance) {
        balance = COMPOUND_FORK.getBalance(user, token);

        uint256 bonusYield = _calculateBonusYield(user, address(token), balance);
        balance += bonusYield;
    }

    /**
     * @dev Get user's shares from the fork
     */
    function getShares(address user, IERC20 token) external view override returns (uint256 shares) {
        shares = COMPOUND_FORK.getShares(user, token);
    }

    /**
     * @dev Get current APY from the fork with time-based bonuses
     */
    function getCurrentApy() external view override returns (uint256 apy) {
        apy = COMPOUND_FORK.getCurrentApy();
    }

    /**
     * @dev Get protocol name with adapter suffix
     */
    function getProtocolName() external pure override returns (string memory name) {
        name = "Compound Adapter";
    }

    /**
     * @dev Get total value locked in the fork
     */
    function getTotalTvl(IERC20 token) external view override returns (uint256 tvl) {
        tvl = COMPOUND_FORK.getTotalTvl(token);
    }

    /**
     * @dev Get exchange rate from the fork
     */
    function getExchangeRate(IERC20 token) external view override returns (uint256 rate) {
        rate = COMPOUND_FORK.getExchangeRate(token);
    }

    /**
     * @dev Check if user is whitelisted (always true for Compound)
     */
    function isWhitelisted(
        address /* user */
    )
        external
        pure
        override
        returns (bool)
    {
        return true;
    }

    /**
     * @dev Calculate bonus yield based on stake duration
     */
    function _calculateBonusYield(address user, address tokenAddress, uint256 amount)
        internal
        view
        returns (uint256 bonusYield)
    {
        uint256 firstDepositTime = userFirstDepositTime[user][tokenAddress];
        if (firstDepositTime == 0) return 0;

        uint256 stakeDuration = block.timestamp - firstDepositTime;

        if (stakeDuration >= 365 days) {
            bonusYield = (amount * 500) / 10000;
        } else if (stakeDuration >= 180 days) {
            bonusYield = (amount * 300) / 10000;
        } else if (stakeDuration >= 90 days) {
            bonusYield = (amount * 200) / 10000;
        } else if (stakeDuration >= 30 days) {
            bonusYield = (amount * 100) / 10000;
        }
    }

    /**
     * @dev Update stake time tracking
     */
    function _updateStakeTime(address user) internal {
        totalStakeTime[user] = block.timestamp;
        emit StakeTimeUpdated(user, totalStakeTime[user]);
    }

    /**
     * @dev Get user's total stake time
     */
    function getUserStakeTime(address user, address token) external view returns (uint256 stakeTime) {
        uint256 firstDeposit = userFirstDepositTime[user][token];
        if (firstDeposit == 0) return 0;
        return block.timestamp - firstDeposit;
    }

    /**
     * @dev Get expected bonus yield for a user
     */
    function getExpectedBonus(address user, address token, uint256 amount) external view returns (uint256 bonusYield) {
        bonusYield = _calculateBonusYield(user, token, amount);
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
     * @dev Add bonus pool tokens (owner function)
     */
    function addBonusPool(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Update owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}
