// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LaunchSwapHarness} from "../policy/LaunchSwapHarness.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IB20} from "base-std/interfaces/IB20.sol";

/// LP6 v2 AUDIT — innocent-operator / FIND-001 fix-adequacy probes.
///
/// These are NOT attacker scenarios. They model a well-meaning operator who
/// launches an ALLOWLIST-compliant B20 through the standard Beryl apparatus and
/// answers three v2 questions the original PoC (PolicyFeeDoS) did not:
///
///   Q1 (fix adequacy) — Does the EXACT deployed fee-path infra set that
///       DeployApparatus folds into the orchestrator (PoolManager,
///       PositionManager, hook, LP locker, fee locker) keep the pool ALIVE
///       *without* the per-token reward recipient? Proves the on-chain
///       orchestrator fold is sufficient for pool liveness and that the reward
///       recipient is NOT a swap-path transfer counterparty (it is only a
///       feeLocker bookkeeping key, credited at storeFees, paid at claim()).
///
///   Q2 (residual gap) — With the pool alive, the B20 LP fees accrue in the fee
///       locker keyed to the reward recipient. Can an UNLISTED reward recipient
///       claim them? It cannot until allowlisted — a recoverable fee-claim lock,
///       NOT a permanent pool brick. Bounds the severity of the on-chain
///       orchestrator NOT auto-folding the (per-token) reward recipient.
///
///   Q3 (defense-in-depth gap) — A later innocent `deauthorize` (e.g. mistaken
///       offboarding) that removes a fee-path address RE-BRICKS the pool. The
///       FIND-001 fold lives only in authorizeAndBind; deauthorize/setFeePathInfra
///       carry no fee-path guard. Mirrors B20PolicyOrchestrator.deauthorize, which
///       forwards updateAllowlist(false) unguarded.
///
/// Controlled experiments on the Base Sepolia fork (B20 precompile in-process).
contract InnocentUserTest is LaunchSwapHarness {
    address constant POLICY_ADMIN = address(0xB0);
    address constant SW = address(0x5A1); // an authorized trader
    uint128 constant BUY_IN = 0.01 ether;

    function _launchAllowlisted(bytes32 salt)
        internal
        returns (Apparatus memory a, address token, PoolKey memory key, uint64 pid)
    {
        (a, token, key) = _launchVanilla(salt, "Innocent B20", "INO");
        pid = _createAllowlist(POLICY_ADMIN);
        _flipScope(IB20(token), OWNER, SCOPE_SENDER, pid);
        _flipScope(IB20(token), OWNER, SCOPE_RECEIVER, pid);
    }

    /// The EXACT addresses DeployApparatus folds into B20PolicyOrchestrator's
    /// `_feePathInfra` — PLUS the authorized trader — but WITHOUT the per-token
    /// reward recipient (OWNER). Mirrors a compliant launch via the on-chain
    /// orchestrator where the caller did NOT pass the reward recipient in
    /// `authorized` (the orchestrator's static infra set cannot know it).
    function _deployedInfraSet(Apparatus memory a) internal pure returns (address[] memory set) {
        set = new address[](6);
        set[0] = POOL_MANAGER;
        set[1] = POSITION_MANAGER;
        set[2] = address(a.hook);
        set[3] = address(a.locker);
        set[4] = address(a.feeLocker);
        set[5] = SW;
        // NOTE: OWNER (reward recipient) intentionally omitted.
    }

    /// Q1 — the deployed infra set (sans reward recipient) keeps the pool ALIVE
    /// through buy->sell->buy->buy. If the reward recipient were a swap-path
    /// counterparty this would brick like FIND-001; it does not.
    function test_q1_deployed_infra_set_keeps_pool_alive_without_reward_recipient() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (Apparatus memory a, address token, PoolKey memory key, uint64 pid) =
            _launchAllowlisted(bytes32(uint256(60)));
        _allowMany(pid, POLICY_ADMIN, _deployedInfraSet(a));
        _rollPastMev();

        uint256 got = _swapWethForB20(SW, key, token, BUY_IN); // buy
        _swapB20ForWeth(SW, key, token, uint128(got / 2)); // sell: accrue B20 fee
        // next swap sweeps the B20 fee (locker -> feeLocker); both allowlisted ->
        // pool stays alive even though the reward recipient is NOT allowlisted.
        assertTrue(_trySwap(SW, key, token, BUY_IN), "pool ALIVE on deployed infra set");
    }

    /// Q2 — an unlisted reward recipient's B20 fee claim is LOCKED but recoverable.
    function test_q2_unlisted_reward_recipient_claim_locks_then_recovers() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (Apparatus memory a, address token, PoolKey memory key, uint64 pid) =
            _launchAllowlisted(bytes32(uint256(61)));
        _allowMany(pid, POLICY_ADMIN, _deployedInfraSet(a));
        _rollPastMev();

        uint256 got = _swapWethForB20(SW, key, token, BUY_IN); // buy
        _swapB20ForWeth(SW, key, token, uint128(got / 2)); // sell: accrue B20 fee
        _swapWethForB20(SW, key, token, BUY_IN); // buy: sweeps B20 fee -> storeFees(OWNER, B20)

        uint256 owed = a.feeLocker.availableFees(OWNER, token);
        assertGt(owed, 0, "B20 LP fee accrued to the reward recipient");

        // reward recipient is NOT allowlisted -> the claim's B20 transfer to OWNER
        // is policy-denied -> reverts. The POOL is unaffected (still alive).
        vm.expectRevert();
        a.feeLocker.claim(OWNER, token);

        // platform authorizes the recipient -> the claim now succeeds (recoverable;
        // no value lost, only delayed). This is the residual gap's full extent.
        _allow(pid, POLICY_ADMIN, OWNER);
        a.feeLocker.claim(OWNER, token);
        assertEq(a.feeLocker.availableFees(OWNER, token), 0, "fees claimed after authorize");
    }

    /// Q3 — a later innocent `deauthorize` of a fee-path address RE-BRICKS the pool.
    function test_q3_deauthorize_of_fee_path_rebricks_pool() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (Apparatus memory a, address token, PoolKey memory key, uint64 pid) =
            _launchAllowlisted(bytes32(uint256(62)));
        _allowMany(pid, POLICY_ADMIN, _deployedInfraSet(a));
        _rollPastMev();

        uint256 got = _swapWethForB20(SW, key, token, BUY_IN); // buy
        _swapB20ForWeth(SW, key, token, uint128(got / 3)); // sell #1: B20 fee pending
        assertTrue(_trySwap(SW, key, token, BUY_IN), "pool alive pre-deauthorize"); // sweeps sell#1 fee
        _swapB20ForWeth(SW, key, token, uint128(got / 3)); // sell #2: fresh B20 fee pending

        // innocent offboarding removes the LP locker from the allowlist (no guard):
        address[] memory drop = new address[](1);
        drop[0] = address(a.locker);
        vm.prank(POLICY_ADMIN);
        REGISTRY.updateAllowlist(pid, false, drop);

        // next swap's fee sweep (locker -> feeLocker) is now policy-denied -> brick.
        assertFalse(
            _trySwap(SW, key, token, BUY_IN), "pool RE-BRICKED after deauthorize of fee-path"
        );
    }
}
