// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProtocol} from "../interfaces/IYieldProtocol.sol";
import {USDC} from "../mocks/USDC.sol";

/**
 * @title AaveFork
 * @dev Fork implementation of Aave protocol with liquid staking
 * This contract replicates the core functionality of the real Aave protocol
 */
contract AaveFork is IYieldProtocol {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public userShares;
    mapping(address => uint256) public totalShares;
    mapping(address => uint256) public totalStaked;

    uint256 public currentApy;
    uint256 public protocolFee;
    uint256 public lastUpdateTime;
    uint256 public accumulatedRewards;
    bool private initialized;
    address public owner;

    constructor() {
        owner = msg.sender;
        lastUpdateTime = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @dev Initialize the protocol
     */
    function initialize(
        uint256 initialApy,
        uint256 _protocolFee
    ) external override onlyOwner {
        require(!initialized, "Already initialized");
        currentApy = initialApy;
        protocolFee = _protocolFee;
        initialized = true;
    }

    /**
     * @dev Deposit tokens and receive liquid staking shares
     */
    function deposit(
        IERC20 token,
        uint256 amount
    ) external override returns (bool success) {
        require(amount > 0, "Invalid amount");

        _accrueYield(token);

        uint256 shares = _calculateShares(address(token), amount);

        token.safeTransferFrom(msg.sender, address(this), amount);

        userShares[msg.sender][address(token)] += shares;
        totalShares[address(token)] += shares;
        totalStaked[address(token)] += amount;

        emit Deposit(msg.sender, amount, shares);
        return true;
    }

    /**
     * @dev Withdraw tokens by burning shares
     */
    function withdraw(
        IERC20 token,
        uint256 amount
    ) external override returns (uint256 amountReceived) {
        require(amount > 0, "Invalid amount");

        _accrueYield(token);

        uint256 userShareBalance = userShares[msg.sender][address(token)];
        uint256 totalSharesForToken = totalShares[address(token)];

        if (amount >= userShareBalance) {
            uint256 vaultBalance = token.balanceOf(address(this));
            amountReceived =
                (userShareBalance * vaultBalance) /
                totalSharesForToken;

            userShares[msg.sender][address(token)] = 0;
            totalShares[address(token)] -= userShareBalance;

            if (amountReceived <= totalStaked[address(token)]) {
                totalStaked[address(token)] -= amountReceived;
            } else {
                totalStaked[address(token)] = 0;
            }

            if (amountReceived > 0) {
                token.safeTransfer(msg.sender, amountReceived);
            }

            emit Withdrawal(msg.sender, userShareBalance, amountReceived);
            return amountReceived;
        }

        uint256 requiredShares = _calculateRequiredShares(
            address(token),
            amount
        );
        require(userShareBalance >= requiredShares, "Insufficient shares");

        amountReceived = _calculateWithdrawalAmount(
            address(token),
            requiredShares
        );

        uint256 availableBalance = token.balanceOf(address(this));
        if (amountReceived > availableBalance) {
            amountReceived = availableBalance;
            requiredShares = _calculateRequiredShares(
                address(token),
                amountReceived
            );
        }

        userShares[msg.sender][address(token)] -= requiredShares;
        totalShares[address(token)] -= requiredShares;

        if (amountReceived <= totalStaked[address(token)]) {
            totalStaked[address(token)] -= amountReceived;
        } else {
            totalStaked[address(token)] = 0;
        }

        if (amountReceived > 0) {
            token.safeTransfer(msg.sender, amountReceived);
        }

        emit Withdrawal(msg.sender, requiredShares, amountReceived);
    }

    /**
     * @dev Get user's token balance (principal + yield)
     */
    function getBalance(
        address user,
        IERC20 token
    ) external view override returns (uint256 balance) {
        uint256 shares = userShares[user][address(token)];
        if (shares > 0 && totalShares[address(token)] > 0) {
            uint256 totalAssets = token.balanceOf(address(this));
            balance = (shares * totalAssets) / totalShares[address(token)];
        }
    }

    /**
     * @dev Get user's shares
     */
    function getShares(
        address user,
        IERC20 token
    ) external view override returns (uint256 shares) {
        shares = userShares[user][address(token)];
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
    function getProtocolName()
        external
        pure
        override
        returns (string memory name)
    {
        name = "Aave Fork";
    }

    /**
     * @dev Get total value locked
     */
    function getTotalTvl(
        IERC20 token
    ) external view override returns (uint256 tvl) {
        tvl = token.balanceOf(address(this));
    }

    /**
     * @dev Get exchange rate (shares to tokens)
     */
    function getExchangeRate(
        IERC20 token
    ) external view override returns (uint256 rate) {
        uint256 totalSharesForToken = totalShares[address(token)];
        if (totalSharesForToken == 0) {
            rate = 1e18;
        } else {
            uint256 totalAssets = token.balanceOf(address(this));
            rate = (totalAssets * 1e18) / totalSharesForToken;
        }
    }

    /**
     * @dev Check if user is whitelisted (no whitelist for Aave)
     */
    function isWhitelisted(address) external pure override returns (bool) {
        return true;
    }

    /**
     * @dev Calculate shares for a given deposit amount
     */
    function _calculateShares(
        address tokenAddress,
        uint256 amount
    ) internal view returns (uint256 shares) {
        uint256 totalSharesForToken = totalShares[tokenAddress];
        if (totalSharesForToken == 0) {
            shares = amount;
        } else {
            uint256 totalAssets = IERC20(tokenAddress).balanceOf(address(this));
            shares = (amount * totalSharesForToken) / totalAssets;
        }
    }

    /**
     * @dev Calculate required shares for a withdrawal amount
     */
    function _calculateRequiredShares(
        address tokenAddress,
        uint256 amount
    ) internal view returns (uint256 requiredShares) {
        uint256 totalSharesForToken = totalShares[tokenAddress];
        if (totalSharesForToken == 0) {
            requiredShares = amount;
        } else {
            uint256 totalAssets = IERC20(tokenAddress).balanceOf(address(this));
            requiredShares = (amount * totalSharesForToken) / totalAssets;
        }
    }

    /**
     * @dev Calculate withdrawal amount for given shares
     */
    function _calculateWithdrawalAmount(
        address tokenAddress,
        uint256 shares
    ) internal view returns (uint256 amount) {
        uint256 totalSharesForToken = totalShares[tokenAddress];
        if (totalSharesForToken == 0) {
            amount = shares;
        } else {
            uint256 totalAssets = IERC20(tokenAddress).balanceOf(address(this));
            amount = (shares * totalAssets) / totalSharesForToken;
        }
    }

    /**
     * @dev Update APY (for testing purposes)
     */
    function setCurrentApy(uint256 newApy) external onlyOwner {
        currentApy = newApy;
    }

    /**
     * @dev Accrue yield by minting USDC based on time and APY
     * Formula: yield = principal * apy * timeElapsed / (365 days * 10000)
     * APY is in basis points (e.g., 500 = 5%)
     */
    function _accrueYield(IERC20 token) internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;

        if (timeElapsed < 60) return;

        uint256 principal = totalStaked[address(token)];
        if (principal == 0 || currentApy == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 yieldAmount = (principal * currentApy * timeElapsed) /
            (365 days * 10000);

        if (yieldAmount > 0) {
            try USDC(address(token)).mint(address(this), yieldAmount) {
                accumulatedRewards += yieldAmount;
            } catch {}
        }

        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Manually accrue yield (can be called by anyone)
     */
    function accrueYield(IERC20 token) external {
        _accrueYield(token);
    }

    /**
     * @dev Add rewards to simulate yield generation (legacy method)
     */
    function addRewards(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
        accumulatedRewards += amount;
    }
}
