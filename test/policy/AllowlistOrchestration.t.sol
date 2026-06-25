// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IB20} from "base-std/interfaces/IB20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LaunchSwapHarness} from "./LaunchSwapHarness.sol";

/// LP4c: an ALLOWLIST-policy B20 denies swaps until the swap path's B20
/// counterparties are authorized — proving the orchestration is both NECESSARY
/// (naive swap reverts) and SUFFICIENT (the minimal set lets it through), and
/// that the swapper itself must be authorized. The minimal set is derived with
/// data, not assumed.
///
/// Derived finding: both a single swap AND sustained (repeated) same-direction
/// trading need exactly {PoolManager, swapper} allowlisted. The fee the LP locker
/// sweeps on the next swap is the PAIRED token (WETH, unpolicied), so it adds no
/// allowlist members. (Sustained trading does require an orthogonal, NON-policy
/// setup step — the LP locker must be an approved depositor of the ClankerFeeLocker
/// — which the harness now wires in _deployApparatus; without it the 2nd swap
/// reverts ClankerFeeLocker.Unauthorized(), unrelated to the allowlist.)
/// Base Sepolia fork.
contract AllowlistOrchestrationTest is LaunchSwapHarness {
    address constant POLICY_ADMIN = address(0xB0);
    address constant SW1 = address(0x5A1);
    uint128 constant SWAP_IN = 0.001 ether;

    function _launchAllowlisted(bytes32 salt)
        internal
        returns (Apparatus memory a, address token, PoolKey memory key, uint64 pid)
    {
        (a, token, key) = _launchVanilla(salt, "Allowlist B20", "ALW");
        pid = _createAllowlist(POLICY_ADMIN);
        _flipScope(IB20(token), OWNER, SCOPE_SENDER, pid);
        _flipScope(IB20(token), OWNER, SCOPE_RECEIVER, pid);
        _rollPastMev();
    }

    /// Derive the minimal single-swap set: grow membership until the first swap
    /// succeeds. nothing -> swapper-only -> +PoolManager == OK. We stop at the
    /// first success so no B20 fees accrue (which would pull in the fee infra and
    /// confound the single-swap derivation).
    function test_derive_minimal_set() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (, address token, PoolKey memory key, uint64 pid) = _launchAllowlisted(bytes32(uint256(20)));

        // (0) nothing allowlisted → naive swap denied (orchestration NECESSARY)
        assertFalse(_trySwap(SW1, key, token, SWAP_IN), "naive swap must be denied");

        // (1) swapper alone is not enough (PoolManager is an unlisted sender)
        _allow(pid, POLICY_ADMIN, SW1);
        assertFalse(_trySwap(SW1, key, token, SWAP_IN), "swapper alone insufficient");

        // (2) + PoolManager → the minimal set authorizes the trade (SUFFICIENT)
        _allow(pid, POLICY_ADMIN, POOL_MANAGER);
        assertTrue(_trySwap(SW1, key, token, SWAP_IN), "{PoolManager, swapper} authorizes the swap");
    }

    /// Complement: PoolManager allowlisted but the swapper is NOT → denied. With
    /// (1) above (swapper-but-not-PoolManager denied), this proves BOTH members
    /// of the minimal set are individually necessary. Fresh pool, so the deny is
    /// purely the swapper's missing authorization (no fee-accrual confound).
    function test_swapper_authorization_required() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (, address token, PoolKey memory key, uint64 pid) = _launchAllowlisted(bytes32(uint256(21)));

        _allow(pid, POLICY_ADMIN, POOL_MANAGER); // infra side authorized...
        // ...but SW1 is not → the take to SW1 (allowlisted receiver gate) is denied
        assertFalse(_trySwap(SW1, key, token, SWAP_IN), "unauthorized swapper denied");
    }

    /// Sustained trading needs no extra allowlist members: with only
    /// {PoolManager, swapper} authorized, a SECOND same-direction swap also
    /// succeeds — the LP fee the locker sweeps in between is the paired token
    /// (WETH, unpolicied). (Depends on the ClankerFeeLocker depositor wiring in
    /// _deployApparatus; that is a setup requirement, not an allowlist member.)
    function test_sustained_trading_same_minimal_set() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (, address token, PoolKey memory key, uint64 pid) = _launchAllowlisted(bytes32(uint256(22)));

        _allow(pid, POLICY_ADMIN, SW1);
        _allow(pid, POLICY_ADMIN, POOL_MANAGER);

        assertTrue(_trySwap(SW1, key, token, SWAP_IN), "1st swap");
        assertTrue(_trySwap(SW1, key, token, SWAP_IN), "2nd swap (sustained, same set)");
    }
}
