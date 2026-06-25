// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {IB20} from "base-std/interfaces/IB20.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";

/// @title B20PolicyOrchestrator
/// @notice Beryl launchpad periphery (NOT part of the vendored Clanker fork).
///         A platform-owned helper that makes a launched B20 compliance-gated:
///         it authorizes the swap path's B20 counterparties in an allowlist
///         policy and binds the token's policy scopes to that policy — atomically,
///         in one owner-gated call. This is the on-chain form of the LP4
///         orchestration (the alternative to running the same registry calls
///         off-chain).
///
/// @dev Trust model: for `authorizeAndBind` to work the orchestrator must be
///      (1) the admin of `policyId` — create it via {createAllowlistPolicy} so
///      this contract is the admin — and (2) a holder of the token's
///      DEFAULT_ADMIN_ROLE, granted by the token admin. It never holds funds; it
///      holds *authority* (who may trade), so it is a high-scrutiny contract for
///      the LP6 audit. Membership/scope changes are owner-only.
contract B20PolicyOrchestrator {
    IPolicyRegistry internal constant REGISTRY = StdPrecompiles.POLICY_REGISTRY;

    address public owner;

    /// @notice Swap/fee-path infrastructure that MUST be allowlisted for any
    ///         compliant pool to keep working — the PoolManager + the LP locker +
    ///         the fee locker (and any peer the hook's unconditional fee sweep
    ///         transfers the B20 through). If an ALLOWLIST policy omits these, the
    ///         hook's `_lpLockerFeeClaim` reverts `PolicyForbids` once B20-side LP
    ///         fees accrue and the pool bricks permanently (LP6 FIND-001). So
    ///         authorizeAndBind ALWAYS folds these in — a compliant launch cannot
    ///         omit them. Reward recipients are per-token and passed by the caller
    ///         in `authorized`.
    address[] private _feePathInfra;

    error NotOwner();
    error ZeroOwner();
    error NoScopes();

    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
    event FeePathInfraUpdated(uint256 count);
    event PolicyCreated(uint64 indexed policyId);
    event Orchestrated(
        address indexed token, uint64 indexed policyId, uint256 authorizedCount, uint256 scopeCount
    );
    event MembershipUpdated(uint64 indexed policyId, bool allowed, uint256 count);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_, address[] memory feePathInfra_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
        _feePathInfra = feePathInfra_;
        emit OwnerUpdated(address(0), owner_);
        emit FeePathInfraUpdated(feePathInfra_.length);
    }

    /// @notice The fee-path infra folded into every {authorizeAndBind} allowlist.
    function feePathInfra() external view returns (address[] memory) {
        return _feePathInfra;
    }

    /// @notice Update the fee-path infra set (e.g. after redeploying a locker).
    function setFeePathInfra(address[] calldata infra) external onlyOwner {
        _feePathInfra = infra;
        emit FeePathInfraUpdated(infra.length);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroOwner();
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Create an ALLOWLIST policy administered by this orchestrator.
    function createAllowlistPolicy() external onlyOwner returns (uint64 policyId) {
        policyId = REGISTRY.createPolicy(address(this), IPolicyRegistry.PolicyType.ALLOWLIST);
        emit PolicyCreated(policyId);
    }

    /// @notice Authorize `authorized` PLUS the fee-path infra in `policyId` and
    ///         bind every scope in `scopes` on `token` to `policyId`, atomically.
    /// @dev Requires this contract to be the policy admin and to hold the token's
    ///      DEFAULT_ADMIN_ROLE. Reverts {NoScopes} if no scopes are given (binding
    ///      nothing would be a silent no-op of the compliance intent). The
    ///      fee-path infra is ALWAYS folded in (LP6 FIND-001) so a compliant pool
    ///      cannot brick on the hook's fee sweep; duplicates with `authorized` are
    ///      harmless (updateAllowlist is idempotent).
    function authorizeAndBind(
        IB20 token,
        uint64 policyId,
        address[] calldata authorized,
        bytes32[] calldata scopes
    ) external onlyOwner {
        if (scopes.length == 0) revert NoScopes();

        address[] memory full = new address[](_feePathInfra.length + authorized.length);
        uint256 n;
        for (uint256 i = 0; i < _feePathInfra.length; i++) full[n++] = _feePathInfra[i];
        for (uint256 i = 0; i < authorized.length; i++) full[n++] = authorized[i];
        if (full.length != 0) {
            REGISTRY.updateAllowlist(policyId, true, full);
        }
        for (uint256 i = 0; i < scopes.length; i++) {
            token.updatePolicy(scopes[i], policyId);
        }
        emit Orchestrated(address(token), policyId, full.length, scopes.length);
    }

    /// @notice Ongoing membership management (e.g. onboard/offboard a trader).
    function authorize(uint64 policyId, address[] calldata accounts) external onlyOwner {
        REGISTRY.updateAllowlist(policyId, true, accounts);
        emit MembershipUpdated(policyId, true, accounts.length);
    }

    function deauthorize(uint64 policyId, address[] calldata accounts) external onlyOwner {
        REGISTRY.updateAllowlist(policyId, false, accounts);
        emit MembershipUpdated(policyId, false, accounts.length);
    }
}
