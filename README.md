# Beryl Clanker fork (B20-precompile token variant)

> **Fork of [clanker-devco/v4-contracts](https://github.com/clanker-devco/v4-contracts)**
> @ `b004c2edda29fa282a16d5d1441a26484f70b37f` (MIT). See [`LICENSE`](./LICENSE).
> Part of Beryl's Faz L launchpad track — see `docs/plans/FAZL-LP2-PLAN.md`.

This fork replaces Clanker's bespoke `ClankerToken` (a constructor-mint EVM ERC-20)
with Base's native **B20** token, created via the `createB20` precompile. The
entire downstream Clanker apparatus — the Uniswap v4 hook, LP locker, and the
Vault / DevBuy / Airdrop / Presale extensions — is **unchanged**, because a
10-agent adversarial analysis (Beryl workflow `wc4ke1pdq`) confirmed they touch
the token **only via standard ERC-20 selectors** (`approve`/`transferFrom`/
`transfer`/`balanceOf`).

## Beryl changes vs upstream

| File | Change |
|---|---|
| `src/utils/ClankerDeployer.sol` | **Rewired:** `new ClankerToken{salt}(…)` → `StdPrecompiles.B20_FACTORY.createB20(ASSET, salt, encodeAssetCreateParams(…), initCalls)` where `initCalls` `batchMint`s the full supply to the factory (delegatecall context). Originating-chain mint gate preserved. |
| `src/ClankerToken.sol` | **Deleted** — B20 is a precompile, not deployable EVM bytecode. |
| `src/hooks/ClankerHook.sol`, `ClankerHookV2.sol` | Removed the **dead** `import {ClankerToken}` (never referenced; blocked the B20-only build). |
| `foundry.toml` | `base = true` (registers the B20 / Policy / Activation precompiles in `base-forge`). |
| `remappings.txt` | Added `base-std/`; removed `@contracts-bedrock/` (Optimism — only the removed `ClankerToken` used it for `IERC7802`/Superchain crosschain). |

**Dropped capabilities** (lived on `ClankerToken`, no B20 analog): on-chain
image/metadata/context (Beryl indexes these off-chain), `verify()`/`isVerified()`,
ERC20Votes, ERC20Permit, ERC20Burnable, and the IERC7802 Superchain cross-chain
mint/burn. The B20 **gains** native policy-state (allow/block/frozen, pause,
supply-cap, rebase, memo).

## Build

```bash
./setup.sh                 # reconstruct lib/ (deps not committed; ~175M)
PATH="$HOME/.foundry/versions/base-v1.1.0:$HOME/.foundry/bin:$PATH" base-forge build
```

Requires Base's Foundry build (`base-forge`); stock Foundry cannot simulate the
B20 precompiles. The full Uniswap v4 + Clanker tree compiles clean against the
B20 precompile (only upstream forge-lint typecast warnings remain).

## Pinned dependency versions (see `setup.sh`)

`forge-std` `77041d2` · `openzeppelin-contracts` `a7d38c7` · `permit2` `cc56ad0` ·
`universal-router` `3663f6d` · `v4-core` `5f00c84` · `v4-periphery` `9628c36` ·
`base-std` (latest). Optimism monorepo intentionally **not** fetched.

## Status

LP2b (compile gate) ✅. Next: LP2c — end-to-end `deployToken` against a Base
Sepolia fork (B20 created · supply on factory · v4 pool · liquidity placed).
**These are money contracts → no mainnet deploy before the LP6 contract audit.**
