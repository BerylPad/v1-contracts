// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IB20} from "base-std/interfaces/IB20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LaunchSwapHarness} from "../policy/LaunchSwapHarness.sol";

/// LP6 AUDIT PoC — confirmed finding "Policy-Denial DoS on swap fee collection".
///
/// On every swap, ClankerHookV2._beforeSwap unconditionally claims LP fees
/// (collectRewardsWithoutUnlock -> ClankerFeeLocker.storeFees), which does a B20
/// transferFrom(LP locker -> fee locker). With an ALLOWLIST policy bound to the
/// transfer scopes, if the LP locker / fee locker / reward recipient are NOT
/// allowlisted, that transfer reverts PolicyForbids and — with no try-catch —
/// bricks ALL future swaps once B20-side fees have accrued.
///
/// This is a CONTROLLED EXPERIMENT: identical buy->sell->buy sequence; the ONLY
/// difference between the two tests is whether the fee-path infra is allowlisted.
/// Brick vs works isolates the cause. Base Sepolia fork.
contract PolicyFeeDoSTest is LaunchSwapHarness {
    address constant POLICY_ADMIN = address(0xB0);
    address constant SW = address(0x5A1);
    uint128 constant BUY_IN = 0.01 ether;

    function _launchAllowlisted(bytes32 salt)
        internal
        returns (Apparatus memory a, address token, PoolKey memory key, uint64 pid)
    {
        (a, token, key) = _launchVanilla(salt, "FeeDoS B20", "FDS");
        pid = _createAllowlist(POLICY_ADMIN);
        _flipScope(IB20(token), OWNER, SCOPE_SENDER, pid);
        _flipScope(IB20(token), OWNER, SCOPE_RECEIVER, pid);
    }

    /// The "LP4 minimal set" {PoolManager, swapper} is INSUFFICIENT: once a sell
    /// accrues B20-side LP fees, the next swap's fee sweep (locker -> feeLocker)
    /// is policy-denied and the pool bricks.
    function test_minimal_set_bricks_pool_on_b20_fee_collection() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (, address token, PoolKey memory key, uint64 pid) = _launchAllowlisted(bytes32(uint256(40)));
        _allow(pid, POLICY_ADMIN, POOL_MANAGER);
        _allow(pid, POLICY_ADMIN, SW);
        _rollPastMev();

        uint256 got = _swapWethForB20(SW, key, token, BUY_IN); // buy: accrues WETH fee
        assertGt(got, 0, "buy delivered B20");
        _swapB20ForWeth(SW, key, token, uint128(got / 2)); // sell: accrues B20 fee

        // next swap's beforeSwap sweeps the B20 fee (locker -> feeLocker); locker
        // is NOT allowlisted -> PolicyForbids -> swap reverts -> pool bricked
        assertFalse(_trySwap(SW, key, token, BUY_IN), "pool BRICKED on B20-fee collection");
    }

    /// Allowlisting the full fee-path infra (LP locker + fee locker + reward
    /// recipient) keeps the pool working through the same sequence — proving the
    /// brick is exactly the missing fee-path authorization (the fix).
    function test_full_fee_infra_set_keeps_pool_working() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (Apparatus memory a, address token, PoolKey memory key, uint64 pid) =
            _launchAllowlisted(bytes32(uint256(41)));

        address[] memory set = new address[](5);
        set[0] = POOL_MANAGER;
        set[1] = SW;
        set[2] = address(a.locker); // LP locker (fee transfer sender)
        set[3] = address(a.feeLocker); // fee locker (fee transfer receiver)
        set[4] = OWNER; // reward recipient
        _allowMany(pid, POLICY_ADMIN, set);
        _rollPastMev();

        uint256 got = _swapWethForB20(SW, key, token, BUY_IN);
        _swapB20ForWeth(SW, key, token, uint128(got / 2));
        assertTrue(_trySwap(SW, key, token, BUY_IN), "pool WORKS with fee-path infra allowlisted");
    }
}
