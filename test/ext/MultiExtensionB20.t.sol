// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import {IBerylPad} from "../../src/interfaces/IBerylPad.sol";
import {BerylPadVault} from "../../src/extensions/BerylPadVault.sol";
import {IBerylPadVault} from "../../src/extensions/interfaces/IBerylPadVault.sol";
import {BerylPadAirdrop} from "../../src/extensions/BerylPadAirdrop.sol";
import {IBerylPadAirdrop} from "../../src/extensions/interfaces/IBerylPadAirdrop.sol";
import {BerylPadUniv4EthDevBuy} from "../../src/extensions/BerylPadUniv4EthDevBuy.sol";
import {IBerylPadUniv4EthDevBuy} from "../../src/extensions/interfaces/IBerylPadUniv4EthDevBuy.sol";
import {BerylPadB20Harness} from "./Helpers.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// LP3c: prove the conservation invariant when Vault + Airdrop + DevBuy run
/// together against a single B20. Earmarks are exact (B20 multiplier = 1
/// identity): vault 20b + airdrop 10b = 30b extensions, pool gets the
/// remaining 70b, and the DevBuy buys out of that 70b with ETH. The full
/// minted 100b is conserved across every sink (no leak, no double-count).
/// Base Sepolia fork.
contract MultiExtensionB20Test is BerylPadB20Harness {
    address constant VAULT_ADMIN = address(0xBEEF);
    address constant ALICE = address(0xA11CE0);
    address constant DEVBUY_RECIPIENT = address(0xD00D);

    uint16 constant VAULT_BPS = 2000; // 20%
    uint16 constant AIRDROP_BPS = 1000; // 10%
    uint256 constant DEV_BUY_ETH = 0.01 ether;

    uint256 constant VAULT_SUPPLY = TOKEN_SUPPLY * VAULT_BPS / 10_000; // 20b
    uint256 constant AIRDROP_SUPPLY = TOKEN_SUPPLY * AIRDROP_BPS / 10_000; // 10b
    uint256 constant POOL_SUPPLY = TOKEN_SUPPLY - VAULT_SUPPLY - AIRDROP_SUPPLY; // 70b

    function test_three_extensions_conservation() public {
        if (!_v4Present()) {
            vm.skip(true);
            return;
        }
        require(UNIVERSAL_ROUTER.code.length > 0, "UniversalRouter absent on fork");

        Apparatus memory a = _deployApparatus();
        BerylPadVault vault = new BerylPadVault(address(a.factory));
        BerylPadAirdrop airdrop = new BerylPadAirdrop(address(a.factory));
        BerylPadUniv4EthDevBuy devBuy =
            new BerylPadUniv4EthDevBuy(address(a.factory), WETH, UNIVERSAL_ROUTER, PERMIT2);

        vm.startPrank(OWNER);
        a.factory.setExtension(address(vault), true);
        a.factory.setExtension(address(airdrop), true);
        a.factory.setExtension(address(devBuy), true);
        vm.stopPrank();

        // Merkle root for the airdrop (single leaf is fine for this test)
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(ALICE, uint256(1_000 ether)))));
        bytes32 root = Hashes.commutativeKeccak256(leaf, leaf);

        IBerylPad.ExtensionConfig[] memory ext = new IBerylPad.ExtensionConfig[](3);
        ext[0] = IBerylPad.ExtensionConfig({
            extension: address(vault),
            msgValue: 0,
            extensionBps: VAULT_BPS,
            extensionData: abi.encode(
                IBerylPadVault.VaultExtensionData({admin: VAULT_ADMIN, lockupDuration: 7 days, vestingDuration: 0})
            )
        });
        ext[1] = IBerylPad.ExtensionConfig({
            extension: address(airdrop),
            msgValue: 0,
            extensionBps: AIRDROP_BPS,
            extensionData: abi.encode(
                IBerylPadAirdrop.AirdropExtensionData({merkleRoot: root, lockupDuration: 1 days, vestingDuration: 0})
            )
        });
        IBerylPadUniv4EthDevBuy.Univ4EthDevBuyExtensionData memory dbData;
        dbData.recipient = DEVBUY_RECIPIENT;
        ext[2] = IBerylPad.ExtensionConfig({
            extension: address(devBuy),
            msgValue: DEV_BUY_ETH,
            extensionBps: 0,
            extensionData: abi.encode(dbData)
        });

        vm.deal(address(this), 1 ether);
        address token = a.factory.deployToken{value: DEV_BUY_ETH}(
            _baseCfg(a, bytes32(uint256(5)), "Multi B20", "MUL", ext)
        );

        // --- exact earmarks ---
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "is B20");
        assertEq(IERC20Min(token).totalSupply(), TOKEN_SUPPLY, "100b minted");
        assertEq(IERC20Min(token).balanceOf(address(vault)), VAULT_SUPPLY, "vault earmark 20b");
        assertEq(IERC20Min(token).balanceOf(address(airdrop)), AIRDROP_SUPPLY, "airdrop earmark 10b");
        assertEq(IERC20Min(token).balanceOf(address(a.factory)), 0, "factory drained");
        assertGt(IERC20Min(token).balanceOf(DEVBUY_RECIPIENT), 0, "devbuy delivered");
        assertEq(IERC20Min(token).balanceOf(address(devBuy)), 0, "devbuy no leftover token");

        // --- conservation: the 70b pool earmark is preserved across every
        // sink the pool supply can land in (PoolManager liquidity + v4 mint
        // dust in the locker + the dev-bought slice now held by the recipient),
        // and vault + airdrop + pool-side == the full 100b minted. ---
        uint256 poolSide = IERC20Min(token).balanceOf(POOL_MANAGER)
            + IERC20Min(token).balanceOf(POSITION_MANAGER) + IERC20Min(token).balanceOf(address(a.locker))
            + IERC20Min(token).balanceOf(DEVBUY_RECIPIENT) + IERC20Min(token).balanceOf(address(a.hook));
        assertEq(poolSide, POOL_SUPPLY, "pool earmark conserved == 70b");

        uint256 grandTotal =
            IERC20Min(token).balanceOf(address(vault)) + IERC20Min(token).balanceOf(address(airdrop)) + poolSide;
        assertEq(grandTotal, TOKEN_SUPPLY, "all 100b conserved across every sink");
    }
}
