// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IYieldProtocol
 * @dev Interface for yield protocol adapters
 */
interface IYieldProtocol {
    event Deposit(address indexed user, uint256 amount, uint256 sharesReceived);
    event Withdrawal(
        address indexed user,
        uint256 shares,
        uint256 amountReceived
    );

    /**
     * @dev Initialize the protocol with initial parameters
     * @param initialApy Initial APY in basis points (e.g., 500 = 5%)
     * @param protocolFee Protocol fee in basis points
     */
    function initialize(uint256 initialApy, uint256 protocolFee) external;

    /**
     * @dev Deposit tokens into the yield protocol
     * @param token The ERC20 token to deposit
     * @param amount Amount of tokens to deposit
     * @return success True if deposit was successful
     */
    function deposit(
        IERC20 token,
        uint256 amount
    ) external returns (bool success);

    /**
     * @dev Withdraw tokens from the yield protocol
     * @param token The ERC20 token to withdraw
     * @param shares Amount of shares to withdraw
     * @return amountReceived Amount of tokens received
     */
    function withdraw(
        IERC20 token,
        uint256 shares
    ) external returns (uint256 amountReceived);

    /**
     * @dev Get user's balance in the protocol
     * @param user User address
     * @param token Token address
     * @return balance User's balance in underlying tokens
     */
    function getBalance(
        address user,
        IERC20 token
    ) external view returns (uint256 balance);

    /**
     * @dev Get user's shares in the protocol
     * @param user User address
     * @param token Token address
     * @return shares User's shares
     */
    function getShares(
        address user,
        IERC20 token
    ) external view returns (uint256 shares);

    /**
     * @dev Get current APY of the protocol
     * @return apy Current APY in basis points
     */
    function getCurrentApy() external view returns (uint256 apy);

    /**
     * @dev Get protocol name
     * @return name Protocol name
     */
    function getProtocolName() external pure returns (string memory name);

    /**
     * @dev Get total value locked in the protocol
     * @param token Token address
     * @return tvl Total value locked
     */
    function getTotalTvl(IERC20 token) external view returns (uint256 tvl);

    /**
     * @dev Get current exchange rate (shares to underlying)
     * @param token Token address
     * @return rate Exchange rate scaled by 1e18
     */
    function getExchangeRate(IERC20 token) external view returns (uint256 rate);

    /**
     * @dev Check if user is whitelisted (for protocols with whitelisting)
     * @param user User address
     * @return isWhitelisted True if user is whitelisted
     */
    function isWhitelisted(
        address user
    ) external view returns (bool isWhitelisted);
}
