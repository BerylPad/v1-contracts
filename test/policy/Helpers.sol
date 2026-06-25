// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {IPolicyRegistry} from "base-std/interfaces/IPolicyRegistry.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";

/// Shared policy harness for LP4. Wraps the singleton IPolicyRegistry precompile
/// (createPolicy / updateAllowlist / updateBlocklist as the policy admin) and the
/// per-token policy-scope flip (IB20.updatePolicy as the token DEFAULT_ADMIN). Kept
/// standalone from BerylPadB20Harness so the pure-mechanics LP4a tests need no
/// Uniswap; LP4b/LP4c inherit BOTH (diamond over forge-std Test).
abstract contract PolicyHarness is Test {
    IPolicyRegistry constant REGISTRY = StdPrecompiles.POLICY_REGISTRY;

    bytes32 constant SCOPE_SENDER = B20Constants.TRANSFER_SENDER_POLICY;
    bytes32 constant SCOPE_RECEIVER = B20Constants.TRANSFER_RECEIVER_POLICY;
    bytes32 constant SCOPE_EXECUTOR = B20Constants.TRANSFER_EXECUTOR_POLICY;
    bytes32 constant SCOPE_MINT = B20Constants.MINT_RECEIVER_POLICY;

    // ---- policy registry (admin-gated membership) ----

    function _createBlocklist(address admin) internal returns (uint64) {
        return REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.BLOCKLIST);
    }

    function _createAllowlist(address admin) internal returns (uint64) {
        return REGISTRY.createPolicy(admin, IPolicyRegistry.PolicyType.ALLOWLIST);
    }

    function _block(uint64 policyId, address admin, address account) internal {
        vm.prank(admin);
        REGISTRY.updateBlocklist(policyId, true, _one(account));
    }

    function _allow(uint64 policyId, address admin, address account) internal {
        vm.prank(admin);
        REGISTRY.updateAllowlist(policyId, true, _one(account));
    }

    function _allowMany(uint64 policyId, address admin, address[] memory accounts) internal {
        vm.prank(admin);
        REGISTRY.updateAllowlist(policyId, true, accounts);
    }

    // ---- per-token scope flip (token DEFAULT_ADMIN-gated) ----

    function _flipScope(IB20 token, address tokenAdmin, bytes32 scope, uint64 policyId) internal {
        vm.prank(tokenAdmin);
        token.updatePolicy(scope, policyId);
    }

    // ---- a vanilla policy-capable B20 (admin holds DEFAULT_ADMIN + MINT_ROLE) ----

    function _newPolicyB20(address tokenAdmin, bytes32 salt) internal returns (IB20 token) {
        bytes memory params = B20FactoryLib.encodeAssetCreateParams("Policy B20", "POL", tokenAdmin, 18);
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = B20FactoryLib.encodeGrantRole(B20Constants.MINT_ROLE, tokenAdmin);
        token = IB20(StdPrecompiles.B20_FACTORY.createB20(IB20Factory.B20Variant.ASSET, salt, params, initCalls));
    }

    function _mint(IB20 token, address minter, address to, uint256 amount) internal {
        vm.prank(minter);
        token.mint(to, amount);
    }

    function _one(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}
