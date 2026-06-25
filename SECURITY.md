# Security Policy

## Scope

This repository contains the smart contracts for the **BerylPad** B20 launchpad —
a fork of [Clanker v4](https://github.com/clanker-devco/v4-contracts) in which the
deployed token is Base's native **B20** precompile token (see [`README.md`](./README.md)).
These contracts handle token deployment, Uniswap v4 LP locking, fee collection,
MEV protection at launch, and B20 policy authorization. Treat all of `src/` as
in-scope.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately via **GitHub Private Vulnerability Reporting** — the *Report a
vulnerability* button under this repository's **Security** tab.

Please include:

- A clear description of the issue.
- Assessed severity (low / medium / high / critical).
- Affected contract(s) and function(s).
- A proof of concept or minimal reproducible example.

We aim to acknowledge within 48 hours and will coordinate a fix and disclosure
timeline with you.

## Audit History

The core hook, LP locker, fee locker, and extension logic is architecturally
identical to upstream Clanker v4, which carries the following audits (see
[`audits/`](./audits/)):

- Cantina v4 Audit — `audits/cantina_v4_audit_1.pdf`
- Macro v4 Audit, Round 1 — `audits/macro_v4_audit_1.pdf`
- Macro v4 Audit, Round 2 — `audits/macro_v4_audit_2.pdf`

The Beryl-specific changes — the `createB20` deployer rewire
(`src/utils/BerylPadDeployer.sol`) and the policy orchestrator
(`src/periphery/B20PolicyOrchestrator.sol`) — are covered by Beryl's own contract
security review; a formal third-party audit is planned before mainnet. The B20
token itself is a chain-level precompile, not part of this repository.

## Please Do Not

- Open a public GitHub issue for a security vulnerability.
- Exploit a vulnerability against any live (mainnet or testnet) deployment.
- Disclose details publicly before a coordinated fix is deployed.
