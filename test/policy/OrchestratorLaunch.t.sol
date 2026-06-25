// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IB20} from "base-std/interfaces/IB20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {B20PolicyOrchestrator} from "../../src/periphery/B20PolicyOrchestrator.sol";
import {LaunchSwapHarness} from "./LaunchSwapHarness.sol";

/// LP4d: the on-chain B20PolicyOrchestrator turns a vanilla-launched B20 into a
/// compliance-gated one in a single owner call — authorize the swap path in an
/// allowlist policy and bind the token's transfer scopes. Proves an authorized
/// trader can trade repeatedly, an unauthorized trader is denied (then onboarded
/// and able to trade), and the orchestration is owner-gated. Base Sepolia fork.
contract OrchestratorLaunchTest is LaunchSwapHarness {
    address constant PLATFORM = address(0xB1A7);
    address constant SW1 = address(0x5A1);
    address constant SW2 = address(0x5A2);
    uint128 constant SWAP_IN = 0.001 ether;
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);

    function _authorizedSet(address trader) internal pure returns (address[] memory infra) {
        // The orchestrator now folds in the fee-path infra itself (LP6 FIND-001
        // fix), so the caller only passes the trader(s).
        infra = new address[](1);
        infra[0] = trader;
    }

    function _scopes() internal pure returns (bytes32[] memory s) {
        s = new bytes32[](2);
        s[0] = SCOPE_SENDER;
        s[1] = SCOPE_RECEIVER;
    }

    function _feePathInfra(Apparatus memory a) internal pure returns (address[] memory f) {
        f = new address[](5);
        f[0] = POOL_MANAGER;
        f[1] = POSITION_MANAGER;
        f[2] = address(a.hook);
        f[3] = address(a.locker);
        f[4] = address(a.feeLocker);
    }

    function test_orchestrated_compliant_launch_and_sustained_trading() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (Apparatus memory a, address token, PoolKey memory key) =
            _launchVanilla(bytes32(uint256(30)), "Orchestrated B20", "ORC");

        // the orchestrator is constructed knowing the fee-path infra to fold in
        B20PolicyOrchestrator orch = new B20PolicyOrchestrator(PLATFORM, _feePathInfra(a));

        // the token admin delegates policy-binding authority to the orchestrator
        vm.prank(OWNER);
        IB20(token).grantRole(DEFAULT_ADMIN_ROLE, address(orch));

        // platform creates the allowlist policy and, in one owner call, authorizes
        // ONLY the trader — the orchestrator folds in the fee-path infra itself
        vm.startPrank(PLATFORM);
        uint64 pid = orch.createAllowlistPolicy();
        orch.authorizeAndBind(IB20(token), pid, _authorizedSet(SW1), _scopes());
        vm.stopPrank();

        _rollPastMev();

        // FIND-001 fix proof: BIDIRECTIONAL trading works (buy -> sell -> buy).
        // Without the fee-path infra folded in, the 3rd swap would brick on the
        // B20-fee sweep (locker not allowlisted). It doesn't, because the
        // orchestrator allowlisted the infra automatically.
        uint256 got = _swapWethForB20(SW1, key, token, SWAP_IN);
        assertGt(got, 0, "buy");
        _swapB20ForWeth(SW1, key, token, uint128(got / 2)); // accrues B20-side fee
        assertGt(_swapWethForB20(SW1, key, token, SWAP_IN), 0, "buy after B20 fee accrual (no brick)");

        // an unauthorized trader is still denied (compliance holds)
        assertFalse(_trySwap(SW2, key, token, SWAP_IN), "unauthorized trader denied");

        // ...until the platform onboards it, then it can trade
        address[] memory add = new address[](1);
        add[0] = SW2;
        vm.prank(PLATFORM);
        orch.authorize(pid, add);
        assertGt(_swapWethForB20(SW2, key, token, SWAP_IN), 0, "onboarded trader trades");
    }

    function test_authorizeAndBind_is_owner_gated() public {
        B20PolicyOrchestrator orch = new B20PolicyOrchestrator(PLATFORM, new address[](0));
        address[] memory empty = new address[](0);
        vm.expectRevert(B20PolicyOrchestrator.NotOwner.selector);
        orch.authorizeAndBind(IB20(address(0xdead)), 1, empty, _scopes());
    }

    function test_authorizeAndBind_requires_scopes() public {
        B20PolicyOrchestrator orch = new B20PolicyOrchestrator(PLATFORM, new address[](0));
        address[] memory empty = new address[](0);
        bytes32[] memory noScopes = new bytes32[](0);
        vm.prank(PLATFORM);
        vm.expectRevert(B20PolicyOrchestrator.NoScopes.selector);
        orch.authorizeAndBind(IB20(address(0xdead)), 1, empty, noScopes);
    }
}
