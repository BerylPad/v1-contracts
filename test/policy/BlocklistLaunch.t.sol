// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IB20} from "base-std/interfaces/IB20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LaunchSwapHarness} from "./LaunchSwapHarness.sol";

/// LP4b: a BLOCKLIST-policy B20 keeps a working Uniswap v4 market (permissive by
/// default) while still enforcing compliance. Model B: launch vanilla through the
/// fork, then the token admin flips the transfer scopes onto a blocklist policy.
/// Market-works is proven with a real post-launch swap; enforcement is proven
/// precisely at the transfer level (PolicyForbids on the exact scope) and again
/// at the swap level. Base Sepolia fork.
contract BlocklistLaunchTest is LaunchSwapHarness {
    address constant POLICY_ADMIN = address(0xB0);
    address constant HOLDER = address(0x7ADE1);
    address constant BLOCKED = address(0x7ADE2);
    uint128 constant SWAP_IN = 0.001 ether;

    function test_vanilla_swap_sanity() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (, address token, PoolKey memory key) = _launchVanilla(bytes32(uint256(10)), "Vanilla Swap", "VSW");
        _rollPastMev();
        uint256 received = _swapWethForB20(HOLDER, key, token, SWAP_IN);
        assertGt(received, 0, "vanilla swap delivered B20");
    }

    function test_blocklist_market_works_and_enforces() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (, address token, PoolKey memory key) = _launchVanilla(bytes32(uint256(11)), "Blocklist B20", "BLK");

        // flip the transfer scopes onto a fresh blocklist policy (token admin = OWNER)
        uint64 pid = _createBlocklist(POLICY_ADMIN);
        _flipScope(IB20(token), OWNER, SCOPE_SENDER, pid);
        _flipScope(IB20(token), OWNER, SCOPE_RECEIVER, pid);

        _rollPastMev();

        // (1) market works: an unlisted trader buys freely (blocklist is permissive)
        uint256 received = _swapWethForB20(HOLDER, key, token, SWAP_IN);
        assertGt(received, 0, "unlisted trader swaps freely under blocklist");

        // block a bad actor
        _block(pid, POLICY_ADMIN, BLOCKED);

        // (2) precise enforcement at the transfer level: HOLDER (clean sender) ->
        // BLOCKED (listed receiver) reverts on the receiver scope exactly
        vm.prank(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, SCOPE_RECEIVER, pid));
        IB20(token).transfer(BLOCKED, 1 ether);

        // (3) enforcement at the swap level: the blocked trader cannot buy either
        // (its swap reverts inside the v4/hook flow)
        _swapExpectRevert(BLOCKED, key, token, SWAP_IN, "");
    }
}
