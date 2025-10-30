// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title USDC
 * @dev Mock USDC token for testing purposes
 * Mimics the real USDC token with 6 decimals
 */
contract USDC is ERC20 {
    uint8 private _decimals;

    /**
     * @dev Constructor that gives msg.sender all of existing tokens
     * @param initialSupply Initial supply of tokens (in base units)
     */
    constructor(uint256 initialSupply) ERC20("USD Coin", "USDC") {
        _decimals = 6;
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mint tokens to a specific address (for testing purposes)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from a specific address (for testing purposes)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
