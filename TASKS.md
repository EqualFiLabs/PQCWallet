## 0) Project Setup & Governance

**Task: Create mono-repo structure**

1. Initialize git repo.
2. Create directories: `/smart-contracts`, `/mobile`, `/docs`, `/ops`.
3. Add root `README.md` with project description.
4. Add `LICENSE` (MIT).
5. Add `.gitignore` and `.editorconfig`.
6. Add `.github/CODEOWNERS` and `.github/PULL_REQUEST_TEMPLATE.md`.
7. Create GitHub issue labels: contracts, mobile, infra, qa, docs, priority-high/med/low, size-S/M.
   DoD: Repo tree shows correct structure, README + LICENSE exist, PR template renders, labels created in GitHub.

**Task: Secrets & env handling**

1. Create root `.env.example` with keys: `RPC_URL`, `BUNDLER_URL`, `ENTRYPOINT_ADDR`.
2. Create `mobile/assets/config.example.json` with equivalent fields.
3. Add `.env` and `mobile/assets/config.json` to `.gitignore`.
4. Write `/docs/dev/secrets.md` with instructions for copying `.env.example` → `.env`.
   DoD: `git status` shows no secrets tracked; `.env.example` and config example exist; secrets doc exists.

**Task: Define branching & CI policy**

1. Create `develop` branch.
2. Protect `main` branch: require PR, require CI passing.
3. Add `/docs/dev/branching.md` describing git flow and versioning (`0.1.0`).
4. Update PR template with checklist for tests, docs, lint.
   DoD: GitHub repo settings show `main` protected, `develop` exists, docs merged, PR template visible.

---

## 1) Smart Contracts (MVP, Base-ready)

**Task: Lock EntryPoint addresses**

1. Add `smart-contracts/contracts/constants/EntryPoint.sol` with Base Sepolia & Base mainnet addresses.
2. Import constants into `Deploy.s.sol`.
3. Commit and run `forge build` to verify.
   DoD: Constants are accessible in scripts, verified by `forge build`.

**Task: Finalize PQCWallet ABI (execute + executeBatch)**

1. Audit PQCWallet interface: confirm `execute` and `executeBatch` signatures.
2. Add NatSpec comments to all external/public functions.
3. Confirm event names/types consistent.
4. Run `forge inspect PQCWallet abi > abi.json`.
   DoD: ABI JSON matches design spec; NatSpec present; events consistent.

**Task: Gas sanity pass (Track A1)**

1. Add Foundry tests invoking `validateUserOp`, `execute`, `executeBatch`.
2. Run `forge snapshot` to record gas costs.
3. Write `/docs/dev/gas.md` with snapshot outputs.
   DoD: Snapshot file exists, doc lists gas usage with clear numbers.

**Task: Add view helpers**

1. Add `function version() public pure returns (bytes32)` returning `"PQCWallet-A1"`.
2. Ensure `currentPkCommit()`, `nonce()`, and `nextPkCommit()` are public.
3. Write Foundry tests for each getter.
   DoD: Tests pass showing correct outputs; `cast call` returns expected values.

**Task: Owner management hardening**

1. Implement two-step ownership transfer: `transferOwnership(address)` sets `pendingOwner`, `acceptOwnership()` finalizes.
2. Emit events on both actions.
3. Write Foundry tests: happy path, reject zero address, revert if non-owner.
   DoD: Tests green; Slither shows no high/medium issues on ownership.

**Task: EntryPoint deposit helpers**

1. Add helper functions: `depositToEntryPoint()` and getter for `EntryPoint.balanceOf`.
2. Write tests depositing ETH and asserting balance increases.
   DoD: Tests confirm deposit reflected in EntryPoint balance.

**Task: WOTS commitment pre-staging UX hook**

1. Add/verify `setNextPkCommit(bytes32)` as optional method.
2. Emit event when set.
3. Write tests ensuring it doesn’t bypass rotation or commit rules.
   DoD: Tests show only valid flow works; events emitted correctly.

**Task: Invariants tests**

1. Write Foundry fuzz tests for:

   * reused WOTS pk reverts,
   * wrong `nextCommit` reverts,
   * nonce increments once per tx.
2. Run fuzz tests with ≥100 runs each.
   DoD: All invariants hold; fuzz suite passes.

**Task: Reversion reason hygiene**

1. Audit all `require`/`revert` statements.
2. Ensure error messages specific and descriptive.
3. Document them in `/docs/errors.md`.
   DoD: Grep finds no generic errors; docs page exists with mapping.

**Task: Slither & Foundry CI**

1. Create `.github/workflows/solidity.yml`.
2. Add job: `forge install`, `forge build`, `forge test -vv`.
3. Add job: run Slither static analysis.
4. Cache dependencies for speed.
   DoD: CI runs automatically; PR shows checks passing.

**Task: License headers & solhint**

1. Add SPDX identifier to all Solidity files.
2. Add `.solhint.json` with rules.
3. Run `npx solhint 'contracts/**/*.sol'`.
   DoD: Lint passes with no errors; all files have SPDX.

**Task: Deploy script (Base Sepolia)**

1. Update `Deploy.s.sol` to read EntryPoint constants.
2. Configure to broadcast with `forge script`.
3. Save output JSON with deployed address + chainId in `/ops/deployments/base-sepolia.json`.
   DoD: Script deploys PQCWallet to Sepolia, JSON artifact exists with correct address.

---

## 2) Infrastructure & Providers

**Task: RPC provider setup (Alchemy)**

1. Create Alchemy apps for Base Sepolia and Base Mainnet.
2. Copy generated RPC URLs into `.env.example` as `RPC_URL_SEPOLIA` and `RPC_URL_MAINNET`.
3. Update `/docs/dev/secrets.md` with setup steps and key usage.
4. Verify `.env` and secrets are gitignored.
   DoD: `.env.example` contains correct keys, docs updated, and secrets never appear in `git status`.

---

**Task: Bundler endpoint (Alchemy AA)**

1. Enable Account Abstraction (AA) in Alchemy dashboard.
2. Record bundler endpoint in `.env.example` as `BUNDLER_URL`.
3. Test endpoint via `curl` to `eth_chainId` and `eth_sendUserOperation` with a dummy payload.
4. Save results to `/docs/dev/bundler.md`.
   DoD: Both RPC calls succeed; bundler URL recorded in env example and docs.

---

**Task: Optional secondary bundler fallback**

1. Add `BUNDLER_URL_FALLBACK` in `.env.example` and `mobile/assets/config.example.json`.
2. Implement simple health probe (`eth_chainId`) in mobile client.
3. Configure retry logic to swap to fallback bundler on primary failure.
   DoD: When primary endpoint is unreachable, app automatically switches and logs fallback usage.

---

**Task: Node health & chain params cache**

1. Create `/mobile/lib/core/chain_config.dart` with fields for chainId, EntryPoint address, fee defaults.
2. Link values to `assets/config.json`.
3. Implement loader in app startup to read and validate file.
4. Add unit test that parses config JSON into chain config object.
   DoD: App can display correct chainId and EntryPoint; unit test passes with expected values.

---

**Task: Flutter project scaffolding**

1. Create Flutter app in `/mobile` with package name `com.equalfi.pqcwallet`.
2. Add dark cyberpunk theme implementation and set it as default.
3. Enable null-safety and fix all analyzer warnings.
4. Add `lints` package and enforce analysis options.
   DoD: `flutter analyze` prints **No issues found**; app boots on iOS/Android emulator with dark theme.

---

**Task: Config loader**

1. Add `assets/config.example.json` → copy to `assets/config.json` in local dev.
2. Implement loader that reads/validates required fields: `rpcUrl`, `entryPoint`, `bundlerUrl`, `walletAddress`.
3. Show red banner toast if any field missing/invalid; block send actions.
4. Register asset in `pubspec.yaml`.
   DoD: Deleting a field triggers red banner; valid file removes banner; `flutter test` includes a parsing test that passes.

---

**Task: Mnemonic generation & storage**

1. On first run, generate 12-word BIP-39 mnemonic (English).
2. Store encrypted using `flutter_secure_storage`; keep in-memory only after biometric unlock.
3. Build **View/Export** screen gated by biometric auth; allow copy/export as text file.
4. Add “Backup completed” flag in secure storage.
   DoD: `flutter test` covers create/read; manual test requires biometric to view/export; backup flag persists across restarts.

---

**Task: ECDSA key derivation**

1. Derive `m/44'/60'/0'/0/0` from mnemonic seed with `bip32`.
2. Keep private key encrypted-at-rest; expose `signDigest(Uint8List)` API.
3. Add test signing a known digest and verifying signature length (65) and r/s non-zero.
   DoD: `flutter test` passes for signing; no plaintext key in logs or files.

---

**Task: WOTS master seed derivation**

1. Derive 32-byte WOTS master seed via HKDF-SHA256 with domain `"WOTS"` from the ECDSA private key bytes.
2. Implement deterministic vector test (fixed mnemonic → fixed master seed).
3. Document derivation in `docs/dev/keys.md`.
   DoD: Unit test asserting exact master seed bytes passes; docs page created.

---

**Task: WOTS per-op derivation**

1. Implement `seed_i = HKDF(master, "WOTS-INDEX-$i")`.
2. Implement WOTS keygen/sign/commit in Dart (w=16, L=67, sha256 chain).
3. Add tests: (a) pk array length 67, (b) sig array length 67, (c) commit length 32.
   DoD: `flutter test` covers the three assertions and passes.

---

**Task: UserOperation builder**

1. Create `UserOperation` class with fields & hex serialization to JSON.
2. Provide sane defaults for gas fields; allow overrides.
3. Add unit test comparing JSON to a reference fixture.
   DoD: `flutter test` passes; JSON matches expected hex formatting.

---

**Task: userOpHash fetcher**

1. Build calldata for `EntryPoint.getUserOpHash(UserOperation)` (signature with empty `signature` field).
2. Call `eth_call` on RPC; parse 32-byte result into `Uint8List`.
3. Handle RPC errors with actionable messages.
   DoD: Unit test with canned RPC response returns exact expected hash; error path surfaces message.

---

**Task: Hybrid signature packer**

1. Pack `ECDSA(65) || WOTSsig(67*32) || WOTSpk(67*32) || nextCommit(32)` into `Uint8List`.
2. Validate exact length **4321 bytes**.
3. Add unit test that asserts byte length and prefix/suffix bytes for sample input.
   DoD: `flutter test` passes; packer returns 4321-byte buffer.

---

**Task: Bundler client**

1. Implement `eth_estimateUserOperationGas`, `eth_sendUserOperation`, `eth_getUserOperationReceipt` with JSON-RPC POST.
2. Add retries with exponential backoff and jitter; classify common errors.
3. Add unit tests mocking 200 / 500 / network timeout responses.
   DoD: Tests pass for success and retry paths; logs show classified errors.

---

**Task: Nonce ↔ WOTS index sync**

1. Add RPC call to wallet `nonce()` before building a UserOp.
2. Derive WOTS `seed_i` using **on-chain nonce**; block send if local index differs.
3. Show error “WOTS index drift: resync nonce and retry.”
4. Persist last used index; never increment until inclusion confirmed.
   DoD: Unit test simulates drift and asserts blocking; happy path uses nonce N and signs once.

---

**Task: Send ETH flow**

1. Build `execute(to, value, "")` calldata for target address and wei amount.
2. Estimate gas via bundler; show network + bundler fee line items.
3. Compute `userOpHash` → sign ECDSA (keystore) + WOTS (index = nonce).
4. Submit via `eth_sendUserOperation`; poll receipt; update activity feed.
   DoD: On Base Sepolia, transfer succeeds and shows inclusion tx hash; `flutter test` has an integration test with mocked bundler.

---

**Task: Receive screen**

1. Display wallet contract address and QR code (checksum encoded).
2. Add copy-to-clipboard and share actions.
3. Optional “fresh address” tip placeholder (non-blocking).
   DoD: QR renders; copying pastes the correct address; share opens native sheet.

---

**Task: Basic activity feed**

1. Maintain local cache of sent operations (hash, to, value, status).
2. Update entries when receipt polling completes.
3. Persist cache to disk; load on startup.
   DoD: After a send, feed shows an item that persists across app restarts.

---

**Task: Error & edge states**

1. Map common bundler errors to UI messages: insufficient funds, verification failed, OOG, mempool reject.
2. Provide retry with same signature when safe (no WOTS rotation).
3. Add generic fallback with error code + raw JSON in dev mode.
   DoD: Manual test triggers each path with mocked responses; messages are distinct and actionable.

---

**Task: No telemetry**

1. Verify `pubspec.yaml` includes no analytics/telemetry dependencies.
2. Add `/docs/privacy.md` stating no tracking in MVP.
3. Ensure crash reporting is disabled in release.
   DoD: `grep -i analytics` finds nothing; privacy doc exists; release build contains no telemetry init code.

---


**Task: ERC-20 ABI integration**

1. Add ABI helpers for `balanceOf(address)`, `decimals()`, `transfer(address,uint256)`, `approve(address,uint256)` in `/mobile/lib/core/erc20.dart`.
2. Implement typed encoders using web3dart ABI codec and return `Uint8List` calldata.
3. Add read helpers `getTokenBalance()` and `getTokenDecimals()` via RPC `eth_call`.
4. Unit-test each encoder against fixed vectors; mock RPC for reads.
   DoD: `flutter test` passes with exact calldata hex fixtures; reading balance/decimals returns expected mock values.

---

**Task: Token list (Base) JSON**

1. Create `mobile/assets/tokens.base.json` with objects `{symbol,address,decimals,logo}` for **USDC** and **WETH** (Base Sepolia + Mainnet).
2. Add loader that validates checksum addresses and required fields.
3. Wire balances view to iterate the loaded list and display symbol/balance.
4. Add schema test to reject invalid token entries.
   DoD: App lists USDC/WETH with correct decimals; invalid entry test fails as expected; assets registered in `pubspec.yaml`.

---

**Task: Send token flow**

1. Build “Send Token” screen with token picker (from token list), recipient, and amount (token units).
2. Convert human amount → smallest units using token `decimals`.
3. Build `execute(token, 0, transfer(to, amount))` calldata.
4. Reuse UserOp build/sign/submit pipeline from ETH send; update activity feed.
   DoD: On Base Sepolia, ERC-20 transfer succeeds and shows inclusion tx hash; unit test verifies calldata encoding.

---

**Task: EIP-2612 Permit encoder**

1. Implement EIP-712 domain builder (name, version, chainId, token address).
2. Implement `Permit` struct encoder `(owner,spender,value,nonce,deadline)` with **deadline = now + ≤60s**.
3. Sign with ECDSA keystore; expose `permitSignature()` returning `v,r,s`.
4. Add unit test using a fixture domain/permit expecting a known digest and signature length 65.
   DoD: `flutter test` passes; digest matches fixture; signature validates locally against provided pubkey.

---

**Task: Permit2 (conditional) support**

1. Add capability check for Permit2 + EIP-1271 support (contract wallet signature) on target token / spender path.
2. Implement Permit2 calldata encoder (single allowance) with short deadline; otherwise **fallback to `approve`**.
3. Add decision matrix: `2612 available → use`, else `Permit2 + 1271 → use`, else `approve`.
4. Unit tests for each branch using mocks.
   DoD: Tests assert correct branch chosen per token capability; calldata encoders produce expected hex.

---

**Task: executeBatch wiring (permit + action)**

1. Build batch calldata `[permit(), transfer()]` using PQCWallet `executeBatch(targets,values,datas)`.
2. Ensure Permit call targets token address; second call targets token `transfer`.
3. Add integration test that compares final `callData` against known reference hex (from Solidity encoder).
4. Validate single UserOp submission path and receipt handling.
   DoD: One UserOp includes both calls; reference hex matches; live Sepolia test sends token with Permit in a single operation.

---

**Task: Fallback approve+transfer batching**

1. Implement batch path `[approve(spender, amount), transfer(to, amount)]` when Permit/Permit2 unsupported.
2. Guard against unlimited approvals—use exact `amount` unless user opts-in (setting off by default).
3. Ensure spender is the intended target (e.g., router if later; for wallet direct transfer, spender = wallet).
4. Add unit test verifying correct spender/amount encoding and batch order.
   DoD: Batch executes successfully on Sepolia; unit test asserts calldata order and bounded approval.

---

**Task: Permit deadlines & nonces UX**

1. Display a countdown timer (≤60s) before sending a Permit-based batch; disable send when deadline passes and regenerate.
2. Fetch token `nonces(owner)` when required (2612 path) and include in the `Permit`.
3. Add error message for expired deadline or mismatched nonce; auto-retry regenerates a fresh permit.
4. Document policy in `/docs/dev/permits.md`.
   DoD: UI blocks after timeout until permit is regenerated; doc merged; tests cover expired permit path.

---

**Task: Readable token amounts & symbols**

1. Implement `formatAmount(amountWei, decimals)` and `parseAmount(input, decimals)` utilities with rounding rules.
2. Show symbol + formatted amount in review screen and activity feed.
3. Tests for edge cases: tiny amounts, max decimals, invalid inputs.
   DoD: All formatting tests pass; UI shows correct representations across tokens.

---

**Task: Token address validation & ENS (optional)**

1. Validate recipient as EIP-55 checksum; if ENS resolution available on Base, resolve `name → address` (optional).
2. Show resolved address preview and warn on mismatch.
3. Add unit tests for checksum pass/fail and ENS mock.
   DoD: Invalid checksum blocks send with clear message; tests pass; ENS resolution flagged as optional if provider unsupported.

---

**Task: Balance/allowance preflight checks**

1. Query token balance before building UserOp; block if insufficient.
2. For fallback `approve+transfer`, check existing allowance and skip `approve` if adequate.
3. Add unit tests for both branches.
   DoD: Preflight prevents underfunded sends; approval step skipped when allowance ≥ amount; tests green.

---

**Task: Error mapping for token paths**

1. Map token-specific reverts (e.g., `transfer returned false`) to actionable UI messages.
2. Capture and display token address/symbol in error view.
3. Provide retry with same signatures where safe (no new WOTS rotation).
   DoD: Manual tests show distinct errors for (return false), (insufficient allowance), (expired permit); retry works when safe.

---

**Task: Token list governance & updates**

1. Add `/docs/dev/tokens.md` describing the token list schema and update process.
2. Add JSON schema validation test for `tokens.base.json`.
3. Add CI check that fails PRs with invalid token entries.
   DoD: Doc merged; schema test present; CI blocks malformed token list PRs.

---


## 5) Gas & Fees UX (incl. bundler cost passthrough)

**Task: Build fee estimator UI**

1. Add review screen section with two rows: “Network fee” and “Bundler fee”.
2. Fetch `estimateUserOperationGas` + `eth_feeHistory` and compute totals.
3. Display maxFeePerGas / priorityFee and allow manual override (advanced toggle).
4. Recompute totals on amount/priority changes.
   DoD: Review screen shows both fees and updates live; manual override changes payload.

**Task: Implement gas calculation service**

1. Create `GasService` to compute `preVerificationGas`, `verificationGasLimit`, `callGasLimit`.
2. Normalize units; clamp to sane floors/ceilings.
3. Surface final values to the UserOp builder.
   DoD: Unit tests pass for conversion/clamping; builder consumes service output.

**Task: Persist user gas preferences (advanced)**

1. Store user’s last priority setting and advanced toggle in encrypted prefs.
2. Preload on app start.
   DoD: Reopen app → settings persist; no plaintext in logs.

**Task: Bundler fee passthrough**

1. Parse bundler quote (if returned) or compute surcharge as % of gas.
2. Render bundler fee separately in UI and in confirmation sheet.
3. Add “Fee details” modal with formula.
   DoD: Bundler fee row present and accurate against payload; modal opens with math.

**Task: Refresh & error states for fees**

1. Add “Refresh” button; disable send while estimating.
2. Map common errors (RPC/bundler down) to snackbars with retry.
   DoD: Manual test shows disabled state during fetch and clear retry UX.

**Task: Fallback gas on estimation failure**

1. Provide conservative constants if estimation throws.
2. Mark UI with “Fallback gas used” warning.
   DoD: Send succeeds with fallback; banner appears.

---

## 6) Security & Key Management Hardening

**Task: Biometric unlock for signing**

1. Require biometric before `signDigest` calls; cache grant for N minutes.
2. Add settings to adjust timeout (default 5m).
   DoD: Without biometric, signing blocked; after unlock, send works for N minutes.

**Task: Backup-before-send gate**

1. Block first mainnet send until backup quiz completed (3 word checks).
2. Add developer override only for debug builds.
   DoD: On prod build, cannot send before backup; on debug, override toggle exists.

**Task: WOTS index reuse guard**

1. Read on-chain `nonce()` before each send; compare to local index.
2. If drift, block and show “Resync nonce” with refresh button.
3. Never increment local index until inclusion confirmed.
   DoD: Simulated drift blocks send; happy path increments post-receipt only.

**Task: Same-sig resubmission path**

1. Allow resubmission with the **same** ECDSA+WOTS sig if previous attempt failed pre-inclusion.
2. Detect inclusion via `eth_getUserOperationReceipt`; prevent double rotation.
   DoD: Cancelled/timeout resubmits keep identical signature bytes.

**Task: Large transfer confirmation**

1. Compute fiat value (if price enabled) or token amount threshold.
2. Insert second confirm screen for > threshold transfers.
   DoD: Threshold hit → extra confirm; turning off removes screen.

**Task: Crash-safe WOTS index writes**

1. On send, write “pending index” to disk; upon receipt, commit to “confirmed index”.
2. Recover on restart: if pending without receipt, do **not** rotate.
   DoD: Unit test simulates crash; index remains correct.

**Task: Secure logs**

1. Scrub logs of secrets, private keys, seeds, and signatures.
2. Add redaction helper and apply in networking/crypto layers.
   DoD: Grep shows no sensitive material; redaction unit tests pass.

---

## 7) Paymaster (user-funded) — optional for MVP+

**Task: Draft paymaster design doc**

1. Write `/docs/dev/paymaster.md` (flow, security model, recoup in USDC/WETH, oracle choice, DoS considerations).
2. Include sequence diagrams and failure modes.
   DoD: Doc reviewed and merged.

**Task: Config toggles for paymaster**

1. Add `usePaymaster` and `payInToken` app settings (hidden behind “Labs”).
2. Wire to UserOp builder to set `paymasterAndData` when enabled.
   DoD: Toggle flips payload between normal and paymaster mode (no chain calls yet).

**Task: Quote & preview UI (mock)**

1. Mock a quote response and render “Gas in USDC” preview with token deduction.
2. Show recoup math and slippage buffer.
   DoD: UI renders with mock values; disabled by default.

*(Implementation of contracts can be scheduled post-MVP.)*

---

## 8) QA, Testing & CI/CD

**Task: Flutter unit test suite**

1. Add tests for mnemonic, HKDF, WOTS keygen/sign/commit, signature packer length, JSON encoding.
2. Ensure `flutter test` runs headless in CI.
   DoD: `flutter test` shows **All tests passed!**

**Task: Bundler integration tests (mock)**

1. Mock HTTP for bundler endpoints; capture request bodies as golden files.
2. Assert `eth_sendUserOperation` payload equals golden.
   DoD: Golden tests pass; diff on change breaks CI.

**Task: Device manual test plan**

1. Create `/ops/test-plan.md` with iOS/Android steps: create wallet, backup, send ETH, send token, permit batch, failure cases.
2. Capture screenshots/video to `/ops/test-artifacts/`.
   DoD: Artifacts exist; checklist completed.

**Task: Contracts CI workflow**

1. `.github/workflows/solidity.yml` builds & tests contracts and runs Slither.
2. Cache Foundry and lib dirs.
   DoD: CI check “foundry” green on PRs.

**Task: Mobile CI workflow**

1. `.github/workflows/flutter.yml` runs `flutter analyze` and `flutter test`.
2. Cache pub deps; set minimum SDK.
   DoD: CI check “flutter” green on PRs.

**Task: Lint gates**

1. Add `solhint` to contracts and enforce in CI.
2. Ensure `dart format .` is clean; add `flutter analyze` as required check.
   DoD: PRs blocked until lints/tests pass.

**Task: Crash-report toggle validation**

1. Confirm no telemetry libs; ensure any crash handlers are disabled.
2. Add unit test ensuring telemetry toggle is false in release build config.
   DoD: Build settings verified; test passes.

---

## 9) Documentation & Compliance

**Task: User docs (backup, PQC, fees)**

1. Write `/docs/user/backup.md`, `/docs/user/pqc.md`, `/docs/user/fees.md`.
2. Keep plain English, include screenshots where helpful.
   DoD: Pages render; links from README work.

**Task: Dev docs (architecture & errors)**

1. Write `/docs/dev/architecture.md` (app layers, key flows, 4337 path).
2. Write `/docs/dev/errors.md` mapping revert/UX codes to explanations/actions.
   DoD: Two docs merged; cross-links added.

**Task: Gas budgets doc**

1. Create `/docs/dev/gas.md` summarizing snapshot values and budgets by action.
   DoD: Numbers match latest snapshot; doc referenced in PR template.

**Task: Permits policy doc**

1. Write `/docs/dev/permits.md` (short deadlines, nonces, fallbacks).
   DoD: Linked from code comments and settings tooltip.

**Task: Risk disclosures**

1. Add `/docs/RISK.md` explaining PQC’s scope (harvest-now-decrypt-later mitigation) and non-coverage.
2. Link from README and onboarding screen.
   DoD: Document visible and linked; onboarding links open it.

**Task: CHANGELOG & versioning**

1. Add `CHANGELOG.md` with `v0.1.0` entry; define semver practice.
2. Update README “Status: MVP v0.1.0”.
   DoD: Changelog present; tag plan documented.

**Task: AGENTS.md addition**

1. Add `AGENTS.md` (build/test commands, task rules, boundaries).
2. Link from README and contributing notes.
   DoD: File present; agents follow it in PRs.

---

## 10) Staging & Launch

**Task: Deploy PQCWallet to Base Sepolia**

1. Configure `Deploy.s.sol` to use EntryPoint constants.
2. Run `forge script … --broadcast` and capture address + chainId.
3. Save artifact to `/ops/deployments/base-sepolia.json`.
4. Update `mobile/assets/config.json` with wallet & EntryPoint.
   DoD: On Sepolia, end-to-end send works from the app; address recorded.

**Task: Staging app build**

1. Create `staging` build flavor: Base Sepolia RPC/bundler config.
2. Produce TestFlight (iOS) and Internal testing (Android) builds.
3. Write `/ops/release-notes/staging.md` with install and test steps.
   DoD: Builds install on devices; smoke test (send 0.001 ETH) succeeds.

**Task: Mainnet readiness config**

1. Add `prod` flavor with Base Mainnet RPC/bundler and EntryPoint.
2. Add in-app toggle (hidden) to display active environment.
3. Verify no debug flags/leaks in prod build.
   DoD: Prod build loads mainnet config without errors; toggle shows “Mainnet”.

**Task: Final UX polish & copy**

1. Review texts on send/review/permit/error screens for clarity.
2. Ensure all buttons have disabled/loading states.
3. Update icons and spacing to match theme.
   DoD: UI review checklist completed; no truncated or ambiguous text.

**Task: Release notes (MVP v0.1.0)**

1. Write `/ops/release-notes/v0.1.0.md` (features, limits, known issues, support email/github).
2. Add `WHAT’S NEW` snippets for app stores.
   DoD: Notes approved and attached to builds.

**Task: Post-launch monitoring checklist**

1. Create `/ops/monitoring.md` (bundler health checks, RPC status links, manual escalation steps).
2. Add simple in-app banner switch for network incidents (config-driven).
   DoD: Doc exists; banner toggle verified in staging.

