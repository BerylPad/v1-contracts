// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IB20} from "base-std/interfaces/IB20.sol";
import {PolicyHarness} from "./Helpers.sol";

/// LP4a: ground the B20 policy model with data, no Uniswap. Proves the four
/// enforcement scopes (sender/receiver/executor on transfers, receiver on mints)
/// and the BLOCKLIST-permissive vs ALLOWLIST-restrictive semantics directly
/// against the in-process B20 + PolicyRegistry precompiles (base=true, no fork).
contract PolicyMechanicsTest is PolicyHarness {
    address constant TOKEN_ADMIN = address(0xAD);
    address constant POLICY_ADMIN = address(0xB0);
    address constant holderA = address(0xA1);
    address constant holderB = address(0xB1);
    address constant holderC = address(0xC1);

    function test_blocklist_permissive_blocks_listed() public {
        IB20 token = _newPolicyB20(TOKEN_ADMIN, keccak256("block"));
        _mint(token, TOKEN_ADMIN, holderA, 1000 ether); // vanilla mint, unrestricted
        _mint(token, TOKEN_ADMIN, holderB, 1000 ether);

        uint64 pid = _createBlocklist(POLICY_ADMIN);
        _flipScope(token, TOKEN_ADMIN, SCOPE_SENDER, pid);
        _flipScope(token, TOKEN_ADMIN, SCOPE_RECEIVER, pid);

        // nobody blocked → blocklist is permissive
        vm.prank(holderA);
        token.transfer(holderB, 1 ether);
        assertEq(token.balanceOf(holderB), 1001 ether, "permissive transfer landed");

        // block holderB → receiver gate forbids `to == holderB`
        _block(pid, POLICY_ADMIN, holderB);
        vm.prank(holderA);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, SCOPE_RECEIVER, pid));
        token.transfer(holderB, 1 ether);

        // ...and the sender gate forbids `from == holderB`
        vm.prank(holderB);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, SCOPE_SENDER, pid));
        token.transfer(holderA, 1 ether);

        // an unrelated pair still moves freely (blocklist only blocks the listed)
        vm.prank(holderA);
        token.transfer(holderC, 1 ether);
        assertEq(token.balanceOf(holderC), 1 ether, "unlisted receiver ok");
    }

    function test_allowlist_denies_then_authorizes() public {
        IB20 token = _newPolicyB20(TOKEN_ADMIN, keccak256("allow"));
        _mint(token, TOKEN_ADMIN, holderA, 1000 ether);

        uint64 pid = _createAllowlist(POLICY_ADMIN);
        _flipScope(token, TOKEN_ADMIN, SCOPE_RECEIVER, pid); // only receiver gated

        // holderC not allowlisted → allowlist denies by default
        vm.prank(holderA);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, SCOPE_RECEIVER, pid));
        token.transfer(holderC, 1 ether);

        // authorize holderC → now it can receive
        _allow(pid, POLICY_ADMIN, holderC);
        vm.prank(holderA);
        token.transfer(holderC, 1 ether);
        assertEq(token.balanceOf(holderC), 1 ether, "allowlisted receiver ok");
    }

    function test_executor_scope_on_transferFrom() public {
        IB20 token = _newPolicyB20(TOKEN_ADMIN, keccak256("exec"));
        _mint(token, TOKEN_ADMIN, holderA, 1000 ether);

        uint64 pid = _createAllowlist(POLICY_ADMIN);
        _flipScope(token, TOKEN_ADMIN, SCOPE_EXECUTOR, pid); // executor (msg.sender) gated

        address EXEC = address(0xE1);
        vm.prank(holderA);
        token.approve(EXEC, type(uint256).max); // approve is never policy-gated

        // EXEC not allowlisted → executor gate forbids (msg.sender != from)
        vm.prank(EXEC);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, SCOPE_EXECUTOR, pid));
        token.transferFrom(holderA, holderB, 1 ether);

        // authorize the executor → transferFrom succeeds
        _allow(pid, POLICY_ADMIN, EXEC);
        vm.prank(EXEC);
        token.transferFrom(holderA, holderB, 1 ether);
        assertEq(token.balanceOf(holderB), 1 ether, "authorized executor ok");
    }

    function test_mint_receiver_always_enforced() public {
        IB20 token = _newPolicyB20(TOKEN_ADMIN, keccak256("mint"));

        uint64 pid = _createAllowlist(POLICY_ADMIN);
        _flipScope(token, TOKEN_ADMIN, SCOPE_MINT, pid);

        address X = address(0x111);
        // X not allowlisted → mint receiver gate forbids
        vm.prank(TOKEN_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyForbids.selector, SCOPE_MINT, pid));
        token.mint(X, 1 ether);

        // authorize X → mint lands
        _allow(pid, POLICY_ADMIN, X);
        vm.prank(TOKEN_ADMIN);
        token.mint(X, 1 ether);
        assertEq(token.balanceOf(X), 1 ether, "allowlisted mint receiver ok");
    }
}
