# Beryl Launchpad Contracts

> **B20-precompile launchpad — a fork of [clanker-devco/v4-contracts](https://github.com/clanker-devco/v4-contracts)**
> @ `b004c2edda29fa282a16d5d1441a26484f70b37f` (MIT). See [`LICENSE`](./LICENSE)
> and [Attribution & naming](#attribution--naming).

## Overview

The on-chain launchpad for **[Beryl](https://github.com/BerylPad)** — a
"DexScreener-for-B20" indexer/explorer for Base's native **B20** token standard
(Beryl hardfork). These contracts let anyone deploy a B20 token in a single
transaction with a Uniswap v4 pool, locked LP, MEV protection, optional
distribution extensions, and B20 **policy-compliance** (allow/block/frozen)
orchestration.

This is a fork of Clanker v4 whose one structural change is the **token**: instead
of deploying a bespoke `ClankerToken` ERC-20, the factory creates Base's native
**B20** via the `createB20` precompile. The entire downstream apparatus — the v4
hook, LP locker, MEV modules, and the Vault / DevBuy / Airdrop / Presale
extensions — is **unchanged**, because they touch the token only through standard
ERC-20 selectors (`approve` / `transfer` / `transferFrom` / `balanceOf`).

> **Status:** end-to-end proven on **Base Sepolia** (apparatus deployed; B20
> launch + v4 pool + locked LP + buy/sell round-trip all live). Contract security
> review done. **No mainnet deployment yet.**

## Contract Architecture

### Core
| Contract | Description |
|---|---|
| `Clanker` | Token factory — orchestrates `deployToken` (B20 create → pool init → LP placement → MEV init → extensions). |
| `utils/ClankerDeployer` | **Beryl rewire:** `createB20` + `batchMint` the full supply to the factory. The one file carrying real fork logic. |
| `ClankerFeeLocker` | Escrow for LP fees with a per-depositor allowlist. |
| `utils/OwnerAdmins` | Owner + admin access control used across the apparatus. |

### Hooks (Uniswap v4)
| Contract | Description |
|---|---|
| `hooks/ClankerHookV2` | Base hook — pool init, swap callbacks, LP-fee sweep, MEV coordination. |
| `hooks/ClankerHookStaticFeeV2` | Static LP-fee strategy (apparatus default). |
| `hooks/ClankerHookDynamicFeeV2` | Dynamic LP-fee strategy. |
| `hooks/ClankerPoolExtensionAllowlist` | Per-pool extension allowlist. |

### LP Lockers
| Contract | Description |
|---|---|
| `lp-lockers/ClankerLpLockerMultiple` | Locks LP, multi-recipient reward distribution (apparatus default). |
| `lp-lockers/ClankerLpLockerFeeConversion` | Fee-conversion locker variant. |

### Extensions (optional, per launch)
| Contract | Description |
|---|---|
| `extensions/ClankerVault` | Lock/vest a bps of supply for later release. |
| `extensions/ClankerAirdrop` · `ClankerAirdropV2` | Merkle-based airdrop. |
| `extensions/ClankerUniv4EthDevBuy` · `ClankerUniv3EthDevBuy` | Dev-buy from the pool at launch. |
| `extensions/ClankerPresaleAllowlist` · `ClankerPresaleEthToCreator` | Allowlist / ETH-to-creator presale. |

### MEV Modules
| Contract | Description |
|---|---|
| `mev-modules/ClankerMevBlockDelay` | Block-delay sniper protection (apparatus default). |
| `mev-modules/ClankerMevTimeDelay` · `ClankerMevDescendingFees` · `ClankerSniperAuctionV0/V2` | Alternative MEV strategies. |

### Beryl periphery (new — not vendored from Clanker)
| Contract | Description |
|---|---|
| `periphery/B20PolicyOrchestrator` | On-chain orchestrator that binds a B20's policy-compliance (allow/blocklist) and folds the fee-path infra into every compliant allowlist so a pool can't brick on the hook's fee sweep. Holds authority, not funds. |

## Deployed Contracts (Base Sepolia · 84532)

Apparatus deployed by [`script/DeployApparatus.s.sol`](./script/DeployApparatus.s.sol).
**Mainnet (8453): not yet deployed.**

| Contract | Address |
|---|---|
| Clanker (factory) | [`0xdb9457dad0d0691a56777a036e2d2b3d830d3da3`](https://sepolia.basescan.org/address/0xdb9457dad0d0691a56777a036e2d2b3d830d3da3) |
| ClankerHookStaticFeeV2 | [`0x2DCfcA9529A498B3bc2A13784EB4989365E768cc`](https://sepolia.basescan.org/address/0x2DCfcA9529A498B3bc2A13784EB4989365E768cc) |
| ClankerLpLockerMultiple | [`0x90e580477a14be33344bab802b5f73d3ec501cbf`](https://sepolia.basescan.org/address/0x90e580477a14be33344bab802b5f73d3ec501cbf) |
| ClankerFeeLocker | [`0x9b5209c45393d73ad97a6c6c168d6ebad1dd959f`](https://sepolia.basescan.org/address/0x9b5209c45393d73ad97a6c6c168d6ebad1dd959f) |
| ClankerPoolExtensionAllowlist | [`0xeb29a9fa3fe29317e2a658567855cbc34c6ed312`](https://sepolia.basescan.org/address/0xeb29a9fa3fe29317e2a658567855cbc34c6ed312) |
| ClankerMevBlockDelay | [`0xE60C0a4B23ebe39f4629f8db7e1536fE91d4D80e`](https://sepolia.basescan.org/address/0xE60C0a4B23ebe39f4629f8db7e1536fE91d4D80e) |
| B20PolicyOrchestrator | [`0x235fbe21115ad5991ffc6412156913aa4f661ccb`](https://sepolia.basescan.org/address/0x235fbe21115ad5991ffc6412156913aa4f661ccb) |

*Example launched token:* [`0xb200…0cd713`](https://sepolia.basescan.org/token/0xb200000000000000000000fbc76c40195c0cd713) (a vanilla B20 with a live v4 pool).

### External dependencies (Base Sepolia)
| Contract | Address |
|---|---|
| Uniswap v4 PoolManager | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| Uniswap v4 PositionManager | `0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80` |
| Universal Router (v4) | `0x492E6456D9528771018DeB9E87ef7750EF184104` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| WETH | `0x4200000000000000000000000000000000000006` |

## What this fork changes vs upstream

| File | Change |
|---|---|
| `src/utils/ClankerDeployer.sol` | **Rewired:** `new ClankerToken{salt}(…)` → `StdPrecompiles.B20_FACTORY.createB20(ASSET, salt, encodeAssetCreateParams(…), initCalls)` where `initCalls` `batchMint`s the full supply to the factory (delegatecall context). Originating-chain mint gate preserved. |
| `src/ClankerToken.sol` | **Deleted** — B20 is a precompile, not deployable EVM bytecode. |
| `src/periphery/B20PolicyOrchestrator.sol` | **New** (Beryl) — B20 policy-compliance orchestration. |
| `src/hooks/ClankerHook.sol`, `ClankerHookV2.sol` | Removed the **dead** `import {ClankerToken}` (never referenced; blocked the B20-only build). |
| `foundry.toml` | `base = true` (registers the B20 / Policy / Activation precompiles in `base-forge`). |
| `remappings.txt` | Added `base-std/`; removed `@contracts-bedrock/` (Optimism — only the removed `ClankerToken` used it for `IERC7802` / Superchain crosschain). |

**Dropped capabilities** (lived on `ClankerToken`, no B20 analog): on-chain
image/metadata/context (Beryl indexes these off-chain), `verify()`/`isVerified()`,
ERC20Votes, ERC20Permit, ERC20Burnable, and the IERC7802 Superchain cross-chain
mint/burn. The B20 **gains** native policy-state (allow/block/frozen, pause,
supply-cap, rebase, memo).

## Build & test

These contracts require **Base's Foundry build (`base-forge`)** — stock Foundry
cannot simulate the B20 / Policy / Activation precompiles. The ~175 MB dependency
tree is not committed; `setup.sh` reconstructs it at the pinned upstream versions.

```bash
./setup.sh                 # reconstruct lib/ at pinned versions + base-std
BASEFORGE="$HOME/.foundry/versions/base-v1.1.0:$HOME/.foundry/bin"
PATH="$BASEFORGE:$PATH" base-forge build
PATH="$BASEFORGE:$PATH" base-forge test          # fork tests need --fork-url <base-sepolia>
```

The full Uniswap v4 + Clanker tree compiles clean against the B20 precompile
(only upstream forge-lint typecast warnings remain). Compiler: Solidity 0.8.28,
viaIR, optimizer 20,000 runs, EVM target Cancun.

## Pinned dependency versions (see `setup.sh`)

`forge-std` `77041d2` · `openzeppelin-contracts` `a7d38c7` · `permit2` `cc56ad0` ·
`universal-router` `3663f6d` · `v4-core` `5f00c84` · `v4-periphery` `9628c36` ·
`base-std` (latest). The Optimism monorepo is intentionally **not** fetched.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for setup, build/test/format
requirements, and the security-critical paths. Report vulnerabilities privately
per [`SECURITY.md`](./SECURITY.md) — never open a public issue.

## Attribution & naming

Forked from [Clanker v4](https://github.com/clanker-devco/v4-contracts) by Clanker
Devco, licensed under MIT (per-file SPDX headers preserved). See [`LICENSE`](./LICENSE)
for the dual copyright notice.

**On naming:** the `Clanker*` contract names are kept **intentionally** (unlike
some forks that rebrand). Keeping them preserves a clean, auditable diff against
upstream (the repo is a GitHub fork — see the "ahead of upstream" view), keeps the
Clanker audit lineage legible, and lets upstream security fixes be merged. The
Beryl-specific code is `B20PolicyOrchestrator` plus the `ClankerDeployer` B20
rewire; everything else is vendored Clanker.

## License

MIT — see [`LICENSE`](./LICENSE).
