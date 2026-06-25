# Contributing

Thanks for your interest in the BerylPad B20 launchpad contracts. This is a fork
of [Clanker v4](https://github.com/clanker-devco/v4-contracts) — read
[`README.md`](./README.md) for exactly what diverges from upstream before changing
anything.

## Fork discipline (read this first)

This repo is a vendored Clanker v4 fork with a thin Beryl delta. To keep the fork
auditable and legally clean:

- **Make changes in the Beryl delta, not the vendored logic.** The genuinely
  Beryl-specific code is `src/utils/BerylPadDeployer.sol` (the `createB20` rewire)
  and `src/periphery/B20PolicyOrchestrator.sol`. Everything else is vendored
  Clanker v4 under renamed (`BerylPad*`) identifiers — avoid modifying it unless
  necessary; it carries upstream's audits.
- **Do not touch `base_mainnet_abis/`.** Those are Clanker's **live-mainnet**
  reference ABIs (not ours), intentionally kept under their original `Clanker*`
  names.
- **Preserve upstream attribution.** Keep the `clanker-devco/v4-contracts` URL,
  the per-file `// SPDX-License-Identifier: MIT` headers, the `LICENSE` copyright,
  and prose like "forked from Clanker" / "upstream Clanker". Do not rebrand these.

## Before you start

- Read the relevant contract code and understand the design.
- Review the audits in [`audits/`](./audits/) — the apparatus is architecturally
  identical to audited Clanker v4.
- For breaking changes or new extensions, open an issue first to discuss.

## Setup

These contracts require **Base's Foundry build (`base-forge`)** — stock Foundry
cannot simulate the B20 / Policy / Activation precompiles (`base = true` in
`foundry.toml`). The dependency tree (~175 MB) is **not** committed; `setup.sh`
reconstructs it at the pinned upstream versions.

```bash
./setup.sh                 # reconstruct lib/ at pinned versions + base-std
BASEFORGE="$HOME/.foundry/versions/base-v1.1.0:$HOME/.foundry/bin"
PATH="$BASEFORGE:$PATH" base-forge build
PATH="$BASEFORGE:$PATH" base-forge fmt           # format before committing
PATH="$BASEFORGE:$PATH" base-forge test          # non-fork tests only

# Fork tests (B20 + Uniswap v4 against forked state) need a Base Sepolia RPC.
# Without --fork-url they are skipped silently:
PATH="$BASEFORGE:$PATH" base-forge test --fork-url <base-sepolia-rpc>
```

## Pull request requirements

- `base-forge build` succeeds.
- `base-forge test --fork-url <base-sepolia>` passes (fork tests included, not just
  the non-fork subset).
- `base-forge fmt --check` passes (config in `foundry.toml [fmt]`).
- Security-critical changes are clearly described in the PR.
- New extensions follow the existing pattern in `src/extensions/`.

## Security-critical paths

Changes to these areas require extra scrutiny and a clear PR description:

- `src/BerylPad.sol` — core token-deployment factory + ownership/admin surface.
- `src/utils/BerylPadDeployer.sol` — the Beryl `createB20` rewire (full-supply mint).
- `src/hooks/` — Uniswap v4 hooks (fee logic, swap path, protocol fee).
- `src/lp-lockers/` — LP locking and reward distribution.
- `src/periphery/B20PolicyOrchestrator.sol` — B20 policy authorization orchestration.

## Reporting security issues

Do **not** open a public issue for vulnerabilities — see [`SECURITY.md`](./SECURITY.md).

## Attribution

This project redistributes upstream Clanker v4 under the MIT License. Preserve the
per-file `// SPDX-License-Identifier: MIT` headers and the upstream copyright notice
in [`LICENSE`](./LICENSE) in any new or modified files.
