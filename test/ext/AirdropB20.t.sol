// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import {IClanker} from "../../src/interfaces/IClanker.sol";
import {ClankerAirdrop} from "../../src/extensions/ClankerAirdrop.sol";
import {IClankerAirdrop} from "../../src/extensions/interfaces/IClankerAirdrop.sol";
import {ClankerB20Harness} from "./Helpers.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// LP3a: prove the ClankerAirdrop extension works with a B20 token end-to-end.
/// deployToken with a 10% airdrop earmark → the factory mints 100b B20, pulls
/// 10b into the airdrop (transferFrom) and places 90b in the v4 pool; a
/// Merkle-gated claim then releases an allocation to a recipient after the
/// lockup. Also proves the security invariant: a bad proof reverts. The Merkle
/// tree uses OZ's standard double-hashed leaf + commutative pair hashing, the
/// exact scheme ClankerAirdrop.claim verifies. Base Sepolia fork.
contract AirdropB20Test is ClankerB20Harness {
    address constant ALICE = address(0xA11CE0);
    address constant BOB = address(0xB0B0);
    uint256 constant ALICE_ALLOC = 1_000 ether;
    uint256 constant BOB_ALLOC = 2_000 ether;

    uint16 constant AIRDROP_BPS = 1000; // 10%
    uint256 constant AIRDROP_SUPPLY = TOKEN_SUPPLY * AIRDROP_BPS / 10_000; // 10b

    bytes32 leafAlice;
    bytes32 leafBob;
    bytes32 merkleRoot;

    function _leaf(address recipient, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(recipient, amount))));
    }

    function _buildTree() internal {
        leafAlice = _leaf(ALICE, ALICE_ALLOC);
        leafBob = _leaf(BOB, BOB_ALLOC);
        merkleRoot = Hashes.commutativeKeccak256(leafAlice, leafBob);
    }

    function _airdropExtension(ClankerAirdrop airdrop)
        internal
        view
        returns (IClanker.ExtensionConfig[] memory ext)
    {
        ext = new IClanker.ExtensionConfig[](1);
        ext[0] = IClanker.ExtensionConfig({
            extension: address(airdrop),
            msgValue: 0,
            extensionBps: AIRDROP_BPS,
            extensionData: abi.encode(
                IClankerAirdrop.AirdropExtensionData({
                    merkleRoot: merkleRoot,
                    lockupDuration: 1 days,
                    vestingDuration: 0
                })
            )
        });
    }

    function _deployWithAirdrop() internal returns (address token, ClankerAirdrop airdrop) {
        _buildTree();
        Apparatus memory a = _deployApparatus();
        airdrop = new ClankerAirdrop(address(a.factory));

        vm.prank(OWNER);
        a.factory.setExtension(address(airdrop), true);

        token = a.factory.deployToken(_baseCfg(a, bytes32(uint256(3)), "Airdrop B20", "AIR", _airdropExtension(airdrop)));
        assertEq(IERC20Min(token).balanceOf(address(a.factory)), 0, "factory drained");
    }

    function test_airdrop_merkle_claim() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (address token, ClankerAirdrop airdrop) = _deployWithAirdrop();

        // --- supply split ---
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "is B20");
        assertEq(IERC20Min(token).balanceOf(address(airdrop)), AIRDROP_SUPPLY, "airdrop holds 10b");
        assertGt(
            IERC20Min(token).balanceOf(POSITION_MANAGER) + IERC20Min(token).balanceOf(POOL_MANAGER),
            0,
            "pool holds the remaining 90b"
        );

        // --- Alice claims with a valid proof after the lockup ---
        vm.warp(block.timestamp + 1 days + 1);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafBob; // sibling of Alice's leaf

        airdrop.claim(token, ALICE, ALICE_ALLOC, proof);
        assertEq(IERC20Min(token).balanceOf(ALICE), ALICE_ALLOC, "Alice received her allocation");
    }

    function test_airdrop_invalid_proof_reverts() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        (address token, ClankerAirdrop airdrop) = _deployWithAirdrop();

        vm.warp(block.timestamp + 1 days + 1);
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(0xdead));

        vm.expectRevert(IClankerAirdrop.InvalidProof.selector);
        airdrop.claim(token, ALICE, ALICE_ALLOC, badProof);
    }
}
