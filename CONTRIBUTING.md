# Contributing

Thanks for your interest in the Beryl / BerylPad B20 launchpad contracts. This is
a fork of [Clanker v4](https://github.com/clanker-devco/v4-contracts) — read
[`README.md`](./README.md) for exactly what diverges from upstream before
changing anything.

## Before You Start

- Read the relevant contract code and understand the design.
- Review the audits in [`audits/`](./audits/) for context on prior security
  decisions — the core apparatus is architecturally identical to audited
  Clanker v4.
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
PATH="$BASEFORGE:$PATH" base-forge test
```

## Pull Request Requirements

- `base-forge build` succeeds.
- `base-forge test` passes.
- `base-forge fmt --check` passes (config in `foundry.toml [fmt]`).
- Security-critical changes are clearly described in the PR.
- New extensions follow the existing pattern in `src/extensions/`.

## Security-Critical Paths

Changes to these areas require extra scrutiny and a clear PR description:

- `src/Clanker.sol` — core token-deployment factory + ownership/admin surface.
- `src/utils/ClankerDeployer.sol` — the Beryl `createB20` rewire (full-supply mint).
- `src/hooks/` — Uniswap v4 hooks (fee logic, swap path, protocol fee).
- `src/lp-lockers/` — LP locking and reward distribution.
- `src/periphery/B20PolicyOrchestrator.sol` — B20 policy authorization orchestration.

## Reporting Security Issues

Do **not** open a public issue for vulnerabilities — see [`SECURITY.md`](./SECURITY.md).

## Attribution

This project redistributes upstream Clanker v4 under the MIT License. Preserve the
per-file `// SPDX-License-Identifier: MIT` headers and the upstream copyright
notice in [`LICENSE`](./LICENSE) in any new or modified files.
