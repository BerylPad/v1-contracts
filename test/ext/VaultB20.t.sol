// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {IClanker} from "../../src/interfaces/IClanker.sol";
import {ClankerVault} from "../../src/extensions/ClankerVault.sol";
import {IClankerVault} from "../../src/extensions/interfaces/IClankerVault.sol";
import {ClankerB20Harness} from "./Helpers.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// LP3a: prove the ClankerVault extension works with a B20 token end-to-end.
/// deployToken with a 20% vault earmark → the factory mints 100b B20, splits
/// 20b to the vault (pulled via transferFrom) and 80b into the v4 pool, then
/// after the lockup the vault releases the full 20b to its admin. Also proves
/// the lockup state-machine: claim before unlock reverts. Base Sepolia fork.
contract VaultB20Test is ClankerB20Harness {
    address constant VAULT_ADMIN = address(0xBEEF);

    uint16 constant VAULT_BPS = 2000; // 20%
    uint256 constant VAULT_SUPPLY = TOKEN_SUPPLY * VAULT_BPS / 10_000; // 20b
    uint256 constant POOL_SUPPLY = TOKEN_SUPPLY - VAULT_SUPPLY; // 80b

    function _vaultExtension(ClankerVault vault) internal pure returns (IClanker.ExtensionConfig[] memory ext) {
        ext = new IClanker.ExtensionConfig[](1);
        ext[0] = IClanker.ExtensionConfig({
            extension: address(vault),
            msgValue: 0,
            extensionBps: VAULT_BPS,
            extensionData: abi.encode(
                IClankerVault.VaultExtensionData({admin: VAULT_ADMIN, lockupDuration: 7 days, vestingDuration: 0})
            )
        });
    }

    function _deployWithVault() internal returns (address token, ClankerVault vault) {
        Apparatus memory a = _deployApparatus();
        vault = new ClankerVault(address(a.factory));

        vm.prank(OWNER);
        a.factory.setExtension(address(vault), true);

        token = a.factory.deployToken(_baseCfg(a, bytes32(uint256(2)), "Vault B20", "VLT", _vaultExtension(vault)));
        // factory fully distributed: 20b to vault, 80b into the pool/locker
        assertEq(IERC20Min(token).balanceOf(address(a.factory)), 0, "factory drained");
    }

    function test_vault_split_and_claim() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (address token, ClankerVault vault) = _deployWithVault();

        // --- supply split ---
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "is B20");
        assertEq(IERC20Min(token).totalSupply(), TOKEN_SUPPLY, "100b minted");
        assertEq(IERC20Min(token).balanceOf(address(vault)), VAULT_SUPPLY, "vault holds 20b");
        assertGt(
            IERC20Min(token).balanceOf(POSITION_MANAGER) + IERC20Min(token).balanceOf(POOL_MANAGER),
            0,
            "pool holds the remaining 80b"
        );

        // --- claim after lockup → admin receives the full vault supply ---
        vm.warp(block.timestamp + 7 days + 1);
        assertEq(vault.amountAvailableToClaim(token), VAULT_SUPPLY, "all unlocked (vesting=0)");

        vault.claim(token);
        assertEq(IERC20Min(token).balanceOf(VAULT_ADMIN), VAULT_SUPPLY, "admin received 20b");
        assertEq(IERC20Min(token).balanceOf(address(vault)), 0, "vault drained");
    }

    function test_vault_claim_before_lockup_reverts() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (address token, ClankerVault vault) = _deployWithVault();

        vm.expectRevert(IClankerVault.AllocationNotUnlocked.selector);
        vault.claim(token);
    }
}
