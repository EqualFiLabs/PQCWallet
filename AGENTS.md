# AGENTS.md


PLEASE INSTALL THE FLUTTER SDK VIA GIT SO YOU CAN PROPERLY TEST

A predictable guide for coding agents working on the EqualFi Labs PQC Wallet repo.  
This repo has two major components:

- `/smart-contracts` → Solidity (Foundry)  
- `/mobile` → Flutter/Dart (cross-platform mobile app)  

Agents should use these commands, styles, and rules when generating or modifying code.

---

## Setup commands

### Contracts
- Install dependencies: `forge install`
- Build: `forge build`
- Run all tests: `forge test -vv`
- Run gas snapshot: `forge snapshot`
- Run static analysis: `slither .`

### Mobile
- Install dependencies: `flutter pub get`
- Analyze code: `flutter analyze`
- Run all tests: `flutter test`
- Start dev app: `flutter run`
- Format: `dart format .`

---

## Code style

### Solidity
- Compiler: `pragma solidity ^0.8.24;`
- SPDX license identifier required at top of every file
- Use NatSpec comments (`@notice`, `@dev`, `@param`, `@return`) for public/external functions
- Always use `uint256` (no `uint`)
- Explicit error messages in `require`
- Events emitted on state changes
- Follow Checks-Effects-Interactions pattern
- Revert reasons must be specific (no generic “fail”)

### Dart / Flutter
- Flutter 3.x strict mode
- State management: Riverpod preferred
- Use `single quotes`, avoid unnecessary semicolons
- Keep widget build methods pure
- Theme: dark, cyberpunk (primary neon teal `#00E5FF`, magenta `#FF3D81`)
- No analytics/telemetry unless explicitly added in `/ops/`

---

## Task guidance

- Break work into tasks **≤ 1 day** (4–6 hours max)
- Each task must include:
  - **Steps** (imperative, reproducible)
  - **Acceptance criteria** (binary, testable; must include command to run and expected output)
  - **Artifacts** (files/branches modified or created)
- All new code must include tests:
  - Solidity → Foundry test in `/smart-contracts/test/`
  - Dart → Flutter test in `/mobile/test/`
- No TODOs, placeholders, or “stubs”
- Use Conventional Commits (`feat:`, `fix:`, `chore:` etc.)

---

## Project-specific notes

- Network focus: **Base Sepolia** (testing), **Base Mainnet** (production)
- EntryPoint addresses: pinned in `/smart-contracts/constants/`
- Bundler: Alchemy AA endpoint configured in `mobile/assets/config.json`
- PQC Track: WOTS signatures must align with on-chain `nonce`
  - One WOTS pk per transaction
  - Reuse forbidden; must block if drift detected
- Permit usage:
  - Prefer EIP-2612
  - Deadlines ≤ 60 seconds
  - Fallback to `approve+transfer` if Permit2 not supported
- Backups:
  - Users must back up 12-word BIP39 before first send
  - Dev mode override allowed in debug builds only

---

## Example acceptance criteria (pattern)

Run forge test -vv → all tests pass, exit code 0

Run flutter test → shows "All tests passed!"

PR opened with title "feat(wallet): add XYZ" and 100% CI green

yaml
Copy code

---

## Agent boundaries

- Do not add new dependencies without justification
- Do not disable lints/tests
- Do not remove license headers