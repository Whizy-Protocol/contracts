pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ProtocolSelector} from "./ProtocolSelector.sol";

/**
 * @title MarketVault
 * @dev ERC4626 vault for a prediction market to track deposits and yield
 *
 * Benefits of ERC4626:
 * - Automatic share-based accounting (shares represent proportional ownership)
 * - Built-in conversion between assets and shares
 * - Standard interface for deposits, withdrawals, and balance queries
 * - Clean separation of principal and yield
 *
 * Each market gets its own vault, making per-market yield tracking trivial.
 */
contract MarketVault is ERC4626 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    address public immutable MARKET;
    ProtocolSelector public immutable PROTOCOL_SELECTOR;
    uint256 public totalYieldWithdrawn;
    bool public yieldEnabled;

    event YieldDeposited(uint256 amount);
    event YieldWithdrawn(address indexed recipient, uint256 amount);
    event VaultRebalanced(uint256 amount);

    error OnlyMarket();
    error YieldDisabled();

    mapping(address => bool) public operators;
    address public owner;

    modifier onlyMarket() {
        if (msg.sender != MARKET) revert OnlyMarket();
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    /**
     * @dev Constructor
     * @param asset_ The underlying asset (e.g., USDC)
     * @param name_ Name of the vault token (e.g., "Market 1 Vault")
     * @param symbol_ Symbol of the vault token (e.g., "MKT1")
     * @param market_ Address of the prediction market contract
     * @param protocolSelector_ Address of the protocol selector for yield
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address market_,
        address protocolSelector_
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        MARKET = market_;
        PROTOCOL_SELECTOR = ProtocolSelector(protocolSelector_);
        yieldEnabled = protocolSelector_ != address(0);
        owner = market_;
        operators[market_] = true;
    }

    /**
     * @dev Get total assets including yield accrued in protocols
     * Override to include both vault balance and balance in yield protocols
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

        if (yieldEnabled && address(PROTOCOL_SELECTOR) != address(0)) {
            uint256 protocolBalance = PROTOCOL_SELECTOR.getTotalBalance(
                address(PROTOCOL_SELECTOR),
                IERC20(asset())
            );
            return vaultBalance + protocolBalance;
        }

        return vaultBalance;
    }

    /**
     * @dev Deposit assets to the vault and optionally deploy to yield protocols
     * Only callable by the market contract
     * Tokens must be transferred to this contract before calling
     */
    function depositForMarket(
        uint256 assets
    ) external onlyMarket returns (uint256 shares) {
        require(assets > 0, "Cannot deposit 0");

        uint256 supply = totalSupply();
        uint256 currentAssets = totalAssets();

        if (supply == 0) {
            shares = assets;
        } else {
            shares = (assets * supply) / currentAssets;
        }

        _mint(MARKET, shares);

        if (yieldEnabled && address(PROTOCOL_SELECTOR) != address(0)) {
            uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

            if (vaultBalance >= assets) {
                IERC20(asset()).safeIncreaseAllowance(
                    address(PROTOCOL_SELECTOR),
                    assets
                );

                try
                    PROTOCOL_SELECTOR.autoDeposit(IERC20(asset()), assets)
                returns (bool success, string memory) {
                    if (success) {
                        emit YieldDeposited(assets);
                    }
                } catch {}
            }
        }

        return shares;
    }

    /**
     * @dev Withdraw assets from the vault (pulls from protocols if needed)
     * Only callable by the market contract
     */
    function withdrawForMarket(
        uint256 assets,
        address recipient
    ) external onlyMarket returns (uint256 shares) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

        if (
            vaultBalance < assets &&
            yieldEnabled &&
            address(PROTOCOL_SELECTOR) != address(0)
        ) {
            uint256 needed = assets - vaultBalance;

            uint256 protocolBalance = PROTOCOL_SELECTOR.getTotalBalance(
                address(PROTOCOL_SELECTOR),
                IERC20(asset())
            );

            uint256 toWithdraw;
            if (needed > (protocolBalance * 95) / 100) {
                toWithdraw = protocolBalance;
            } else {
                toWithdraw = needed + (needed / 100) + 100;
            }

            try
                PROTOCOL_SELECTOR.autoWithdraw(IERC20(asset()), toWithdraw)
            returns (uint256 amountReceived) {
                if (amountReceived > needed) {
                    totalYieldWithdrawn += (amountReceived - needed);
                }
            } catch {
                revert("Insufficient liquidity");
            }
        }

        uint256 maxAvailable = maxWithdraw(MARKET);
        if (assets > maxAvailable) {
            uint256 shortage = assets - maxAvailable;

            uint256 tolerance = assets / 10000;
            if (tolerance < 1000) tolerance = 1000;

            require(
                shortage <= tolerance,
                "Requested amount exceeds available balance"
            );
            assets = maxAvailable;
        }

        shares = withdraw(assets, recipient, MARKET);
    }

    /**
     * @dev Calculate current yield earned (total assets - total deposits)
     * @return currentYield Current unrealized yield
     */
    function getCurrentYield() external view returns (uint256 currentYield) {
        uint256 assets = totalAssets();
        uint256 totalShares = totalSupply();

        if (totalShares == 0) {
            return 0;
        }

        if (assets > totalShares) {
            currentYield = assets - totalShares;
        }
    }

    /**
     * @dev Get yield for a specific share holder (e.g., a bet)
     * @param shares Number of shares held
     * @return yieldAmount Yield amount for those shares
     */
    function getYieldForShares(
        uint256 shares
    ) external view returns (uint256 yieldAmount) {
        uint256 totalCurrentYield = this.getCurrentYield();
        uint256 totalShares = totalSupply();

        if (totalShares == 0) {
            return 0;
        }

        yieldAmount = (totalCurrentYield * shares) / totalShares;
    }

    /**
     * @dev Calculate assets value for given shares (includes yield)
     * @param shares Number of shares
     * @return assets Asset value including proportional yield
     */
    function convertToAssetsWithYield(
        uint256 shares
    ) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /**
     * @dev Rebalance vault funds to optimal yield protocol
     * Can be called by authorized operators (backend service)
     */
    function rebalance() external onlyOperator {
        if (!yieldEnabled || address(PROTOCOL_SELECTOR) == address(0)) {
            revert YieldDisabled();
        }

        uint256 protocolBalance = PROTOCOL_SELECTOR.getTotalBalance(
            address(this),
            IERC20(asset())
        );

        if (protocolBalance == 0) {
            return;
        }

        uint256 withdrawn = PROTOCOL_SELECTOR.autoWithdraw(
            IERC20(asset()),
            protocolBalance
        );

        if (withdrawn > 0) {
            IERC20(asset()).safeIncreaseAllowance(
                address(PROTOCOL_SELECTOR),
                withdrawn
            );
            PROTOCOL_SELECTOR.autoDeposit(IERC20(asset()), withdrawn);
            emit VaultRebalanced(withdrawn);
        }
    }

    /**
     * @dev Add operator who can rebalance the vault
     */
    function addOperator(address operator) external onlyMarket {
        operators[operator] = true;
    }

    /**
     * @dev Remove operator
     */
    function removeOperator(address operator) external onlyMarket {
        operators[operator] = false;
    }

    /**
     * @dev Emergency function to recover stuck tokens (only market can call)
     */
    function emergencyWithdraw(
        IERC20 token,
        address recipient
    ) external onlyMarket {
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(recipient, balance);
        }
    }

    /**
     * @dev Get comprehensive vault info
     */
    function getVaultInfo()
        external
        view
        returns (
            uint256 totalAssetsInVault,
            uint256 totalShares,
            uint256 currentYield,
            uint256 yieldWithdrawn,
            uint256 exchangeRate
        )
    {
        totalAssetsInVault = totalAssets();
        totalShares = totalSupply();
        currentYield = this.getCurrentYield();
        yieldWithdrawn = totalYieldWithdrawn;
        exchangeRate = totalShares > 0
            ? (totalAssetsInVault * 1e18) / totalShares
            : 1e18;
    }
}
