// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";
import {ClankerB20Harness} from "./ext/Helpers.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// LP2c-full: end-to-end forked Clanker.deployToken on a Base Sepolia fork.
/// Deploys the full apparatus (factory + mined v4 hook + locker + feeLocker + MEV),
/// wires it, and calls deployToken → asserts a B20 is created, the 100b supply is
/// minted to the factory and distributed (factory drained), and the v4 pool + LP
/// position are placed. This is the complete mint-timing + pool proof of the fork.
/// The apparatus bring-up + config builder now live in ext/Helpers.sol (shared
/// with the LP3 extension suite); assertions here are unchanged from LP2c.
contract ForkedClankerE2ETest is ClankerB20Harness {
    function test_fullFactory_deployToken_e2e() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }

        Apparatus memory a = _deployApparatus();

        IClanker.ExtensionConfig[] memory none = new IClanker.ExtensionConfig[](0);
        address token = a.factory.deployToken(_baseCfg(a, bytes32(uint256(1)), "Minimal Clanker B20", "MINI", none));

        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "B20 created");
        assertEq(IERC20Min(token).totalSupply(), TOKEN_SUPPLY, "100b minted");
        assertEq(IERC20Min(token).balanceOf(address(a.factory)), 0, "factory drained into pool/locker");
        assertGt(
            IERC20Min(token).balanceOf(POSITION_MANAGER) + IERC20Min(token).balanceOf(POOL_MANAGER),
            0,
            "supply in v4 pool"
        );
    }
}
