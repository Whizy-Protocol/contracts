// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title AccessControl
 * @dev Contract that provides basic access control with owner and pausable functionality
 */
contract AccessControl {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event Paused(address account);
    event Unpaused(address account);

    address private _owner;
    bool private _paused;

    error NotOwner();
    error NotAuthorized();
    error AlreadyInitialized();
    error IsPaused();

    /**
     * @dev Modifier to check if caller is the owner
     */
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    /**
     * @dev Modifier to check if contract is not paused
     */
    modifier whenNotPaused() {
        if (_paused) revert IsPaused();
        _;
    }

    /**
     * @dev Modifier to check if contract is paused
     */
    modifier whenPaused() {
        if (!_paused) revert NotAuthorized();
        _;
    }

    /**
     * @dev Constructor that initializes the owner
     */
    constructor() {
        _owner = msg.sender;
        _paused = false;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Initialize owner (alternative to constructor for proxy patterns)
     * @param initialOwner The initial owner address
     */
    function initializeOwner(address initialOwner) external {
        if (_owner != address(0)) revert AlreadyInitialized();
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @dev Returns true if the contract is initialized
     */
    function isInitialized() external view returns (bool) {
        return _owner != address(0);
    }

    /**
     * @dev Returns true if the given account is the owner
     * @param account The account to check
     */
    function isOwner(address account) external view returns (bool) {
        return account == _owner;
    }

    /**
     * @dev Returns the current owner
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @dev Transfers ownership of the contract to a new account
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /**
     * @dev Returns true if the contract is paused
     */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @dev Asserts that the caller is the owner
     */
    function assertOwner() external view {
        if (msg.sender != _owner) revert NotOwner();
    }

    /**
     * @dev Asserts that the specified account is the owner
     * @param account The account to check as owner
     */
    function assertOwner(address account) external view {
        if (account != _owner) revert NotOwner();
    }

    /**
     * @dev Asserts that the contract is not paused
     */
    function assertNotPaused() external view {
        if (_paused) revert IsPaused();
    }
}
