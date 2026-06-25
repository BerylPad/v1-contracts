// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ClankerB20Harness} from "./Helpers.sol";

/// LP3b feasibility gate: the Univ4 ETH DevBuy extension swaps through the
/// UniversalRouter, so the forked Base Sepolia state must carry its bytecode
/// (Permit2 is canonical). This probe records the on-chain fact that drives the
/// LP3b path decision (full e2e vs. mock). Skips cleanly without --fork-url.
contract DevBuyProbeTest is ClankerB20Harness {
    function test_universalRouter_present_on_fork() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        assertGt(UNIVERSAL_ROUTER.code.length, 0, "UniversalRouter has bytecode on the fork");
        assertGt(PERMIT2.code.length, 0, "Permit2 has bytecode on the fork");
        emit log_named_uint("UniversalRouter code bytes", UNIVERSAL_ROUTER.code.length);
        emit log_named_uint("Permit2 code bytes", PERMIT2.code.length);
    }
}
