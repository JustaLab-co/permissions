# JustaPermissionManager

## Deployment Addresses

**JustaPermissionManager**: `0xf1b40E3D5701C04d86F7828f0EB367B9C90901D8`

**Deployed on:**

| Network          | Chain ID | Testnet          | Chain ID |
| ---------------- | -------- | ---------------- | -------- |
| Ethereum Mainnet | 1        | Sepolia          | 11155111 |
| Base             | 8453     | Base Sepolia     | 84532    |
| Optimism         | 10       | OP Sepolia       | 11155420 |
| Arbitrum One     | 42161    | Arbitrum Sepolia | 421614   |
| BSC              | 56       | BSC Testnet      | 97       |
| Linea            | 59144    | Linea Sepolia    | 59141    |
| Avalanche        | 43114    | Avalanche Fuji   | 43113    |
| Celo             | 42220    | Celo Sepolia     | 11142220 |
| Flare            | 14       | Flare Coston2    | 114      |
| Ink              | 57073    | Ink Sepolia      | 763373   |
| DOS              | 7979     |                  |          |
| Gnosis           | 100      | -                | -        |
| Arc              | 5042     | Arc Testnet      | 5042002  |
| Polygon          | 137      | -                | -        |
| Robinhood Chain  | 4663     | -                | -        |
| Soneium          | 1868     | -                | -        |
| HyveChain        | 7847     | -                | -        |
| Unichain         | 130      | -                | -        |
| Monad            | 143      | -                | -        |

## Overview

`JustaPermissionManager` is a Solidity smart contract that provides a delegation layer for [JustanAccount](https://github.com/justaname-id/justanaccount) smart accounts. It enables granular access control through delegated permissions, allowing account owners to grant time-limited permissions to "spenders" (delegated addresses) to execute specific actions on their behalf with fine-grained call authorization and spending limits.

## Features

- **Time-Bound Permissions**: Enforce temporal access control with start/end timestamps. Supports future-dated permissions and time-limited delegation.
- **Call Authorization**: Whitelist-based call permissions specifying exact (target, selector) pairs with wildcard support for flexible policies.
- **Call Checkers**: Optional external validators that receive full calldata for parameter validation, enabling sophisticated authorization logic.
- **Flexible Spend Limits**: Per-token spending limits with multiple period types (Minute, Hour, Day, Week, Month, Forever) and multipliers for extended periods. All periods are aligned to the permission start time.
- **Multiple Limits Per Token**: Support simultaneous period-based limits (e.g., hourly AND daily limits on the same token).
- **Native Token Support**: ERC-7528 convention for ETH spending limits using the `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE` address.
- **ERC20 Protection**: Automatic approval revocation after execution prevents malicious contracts from leaving backdoor approvals.
- **Permit2 Integration**: Support for Uniswap's Permit2 token approval standard with automatic lockdown after execution.
- **Conservative Spend Tracking**: Uses `max(calldata_amounts, balance_delta)` to prevent gaming through flash loans or state manipulation.
- **EIP-712 Signatures**: Typed structured data hashing for secure off-chain signing and verification.
- **Reentrancy Protection**: Guards against reentrancy attacks on all state-modifying functions.

## Architecture

The contract system consists of two main components:

### JustaPermissionManager (Main Contract)

The primary permission management contract that inherits from:

- EIP712 (OpenZeppelin's EIP-712 implementation)
- ReentrancyGuard (Solady's reentrancy protection)

#### Key Libraries Used

- `SafeERC20` - Safe ERC20 token transfers
- `ERC165Checker` - Token type detection (ERC721/ERC1155 rejection)
- `DateTimeLib` (Solady) - Calendar period calculations
- `DynamicArrayLib` (Solady) - Dynamic array management
- `LibSort` (Solady) - Sorting utilities
- `LibBytes` (Solady) - Byte manipulation
- `SafeTransferLib` (Solady) - Token transfer helpers

### ICallChecker (Interface)

An interface for external call validators:

```solidity
interface ICallChecker {
    function canExecute(
        bytes32 permissionHash,
        address account,
        address spender,
        address target,
        uint256 value,
        bytes calldata data
    ) external view returns (bool);
}
```

## Data Structures

### Permission

Complete delegated permission with time bounds:

```solidity
struct Permission {
    address account;          // Account owner
    address spender;          // Delegated spender
    uint48 start;             // Permission valid start time
    uint48 end;               // Permission valid end time
    uint256 salt;             // Unique salt for differentiation
    CallPermission[] calls;   // Array of call permissions
    SpendLimit[] spends;      // Array of spend limits
}
```

### CallPermission

Specifies allowed function calls with optional validation:

```solidity
struct CallPermission {
    address target;      // Contract address (or ANY_TARGET wildcard)
    bytes4 selector;     // Function selector (or ANY_FN_SEL wildcard)
    address checker;     // Optional call validator (address(0) = no checker)
}
```

### SpendLimit

Recurring spending allowance with flexible periods:

```solidity
struct SpendLimit {
    address token;           // Token to limit (or NATIVE_TOKEN)
    uint160 allowance;       // Max spend per period
    PeriodUnit unit;         // Period type (Minute-Month or Forever)
    uint16 multiplier;       // Period multiplier (1-65535)
}
```

### PeriodUnit

```solidity
enum PeriodUnit {
    Minute,     // 60 seconds
    Hour,       // 3600 seconds
    Day,        // 86400 seconds
    Week,       // 604800 seconds
    Month,      // Calendar month (uses addMonths for day clamping)
    Forever     // One-time allowance for entire permission duration
}
```

All periods (except Forever) are aligned to the permission's start time, ensuring every period is exactly the intended length with no premature resets.

### PeriodSpend

Spend tracking for current period:

```solidity
struct PeriodSpend {
    uint48 start;         // Period start timestamp
    uint48 end;           // Period end timestamp
    uint160 spend;        // Cumulative spend in this period
}
```

## Constants

### Wildcard Constants

```solidity
address public constant ANY_TARGET = 0x3232323232323232323232323232323232323232;
bytes4 public constant ANY_FN_SEL = 0x32323232;
bytes4 public constant EMPTY_CALLDATA_FN_SEL = 0xe0e0e0e0;
```

### Token Constants

```solidity
address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
```

## Key Functions

### Account Owner Functions

- `approve(Permission calldata permission)`: Approve a permission with full validation. Validates time bounds, call permissions, spend limits, and prevents privilege escalation. Caller must be the account owner.
- `revoke(Permission calldata permission)`: Revoke a permission by the account owner.
- `revokeAsSpender(Permission calldata permission)`: Revoke a permission by the spender.

### Execution Functions

- `executeBatch(Permission calldata permission, BaseAccount.Call[] calldata calls)`: Execute multiple calls with permission validation. The 8-step process includes:
  1. Check permission approved and not revoked
  2. Validate time bounds
  3. Check call authorization and run checkers (fail-fast)
  4. Setup spend tracking (collect ERC20s, parse calldata)
  5. Record ERC20 balances before execution
  6. Execute all calls via JustanAccount
  7. Revoke ERC20 and Permit2 approvals (security critical)
  8. Check spend limits using max(calldata_sum, balance_delta)

### View Functions

- `isApproved(bytes32 permissionHash)`: Check if permission is approved.
- `isRevoked(bytes32 permissionHash)`: Check if permission is revoked.
- `getLastUpdatedPeriod(bytes32 permissionHash, bytes32 spendLimitHash)`: Get last updated spend period info.
- `getCurrentPeriod(SpendLimit calldata spendLimit, uint48 permissionStart, uint48 permissionEnd)`: Calculate current spend period.
- `getHash(Permission calldata permission)`: Calculate EIP-712 permission hash.
- `startOfSpendPeriod(uint256 unixTimestamp, PeriodUnit unit, uint16 multiplier, uint256 permissionStart)`: Get period start for given timestamp, aligned to the permission start time.

## Security Model

### Privilege Escalation Prevention

- Cannot target the PermissionManager contract itself
- Cannot target the account being delegated from
- Prevents spenders from granting themselves additional permissions

### Approval Revocation Safety

- Hard failures if ERC20 approval revocation doesn't complete
- Automatic Permit2 lockdown after execution
- Ensures no leftover approvals that could be exploited

### Call Checker Validation

- Checkers must have deployed code (no EOA checkers)
- All matching checkers must approve (AND logic)
- Fail-fast on first rejection

### Spend Tracking

- Conservative approach using max of calldata amounts and balance deltas
- Permission-start-aligned periods prevent timing attacks (no epoch alignment exploits)

### Empty Spend Limits Behavior

Permissions with an empty `spends` array will cause **all token and ETH transfer operations to revert** with `JustaPermissionManager_NoSpendPermissions`. This is intentional behavior to prevent untracked token outflows:

- **ERC20 transfers** (`transfer`, `transferFrom`, `approve`): Will revert
- **Native ETH transfers** (calls with `value > 0`): Will revert
- **Non-value operations** (e.g., view calls, state changes without token movement): Will succeed

To allow token or ETH operations, you **must** configure appropriate spend limits for each token that may be transferred. This ensures all outflows are tracked and enforced against the configured limits.

**Warning:** Pre-approved assets on the account (e.g., existing ERC20 allowances to third-party contracts) may still be transferred if a whitelisted contract internally calls `transferFrom`. These indirect transfers bypass spend tracking. Account owners should review and revoke any unnecessary pre-existing approvals before delegating permissions.

## Storage Layout

```solidity
// Permission approval tracking
mapping(bytes32 permissionHash => bool approved) internal _isApproved;

// Permission revocation tracking
mapping(bytes32 permissionHash => bool revoked) internal _isRevoked;

// Spend limit period tracking
mapping(bytes32 permissionHash => mapping(bytes32 spendLimitHash => PeriodSpend))
    internal _lastUpdatedPeriod;
```

## Events

```solidity
event PermissionApproved(bytes32 indexed permissionHash, Permission permission);
event PermissionRevoked(bytes32 indexed permissionHash);
event CallsExecuted(bytes32 indexed permissionHash);
event SpendLimitUsed(bytes32 indexed permissionHash, address indexed token, PeriodSpend periodSpend);
```

## Integration with JustanAccount

JustaPermissionManager acts as an owner of JustanAccount instances:

1. Deploy a JustanAccount instance
2. Add JustaPermissionManager as an owner via `addOwnerAddress()`
3. Create a Permission struct with calls and spends
4. Account owner calls `approve(permission)`
5. Spender calls `executeBatch(permission, calls)`
6. Revoke when no longer needed

## Influences & Acknowledgments

This implementation was influenced by and builds upon:

- **[JustanAccount](https://github.com/justaname-id/justanaccount)**: The target smart account contract that JustaPermissionManager delegates to.
- **[Solady](https://github.com/Vectorized/solady)**: Optimized utility libraries including DateTimeLib, DynamicArrayLib, SafeTransferLib, and ReentrancyGuard.
- **[OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)**: Standard implementations for EIP-712, SafeERC20, and ERC165Checker.
- **[Uniswap Permit2](https://github.com/Uniswap/permit2)**: Token approval standard integration for enhanced security.
