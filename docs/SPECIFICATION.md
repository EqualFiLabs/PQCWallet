# EqualFi PQC Wallet — Design Specification (v1.3 • 2025-10-16)

*Quantum-resilient smart vault that lives beside a normal EOA, with user-selectable custody (Seed or Passkey) and per-transaction security mode (on-chain PQC vs attested).*

---

## 1) Purpose and scope

EqualFi’s PQC Wallet is a two-part experience:

* A **normal EOA** for everyday use, created and held on the mobile device.
* An optional **PQC Secure Smart Vault** implemented as an ERC-4337 smart account that adds post-quantum guarantees using **WOTS+** plus staged key rotation.

For each Vault transaction, users choose:

* **Most secure**: on-chain WOTS+ verification. Higher gas, registry not required.
* **Attested**: off-chain verification with an **EIP-712 attestation** from an allow-listed prover. Much cheaper, requires `ProverRegistry`.

At onboarding, users choose custody:

* **Seed Mode**: classic mnemonic backup.
* **Passkey Mode**: “invisible wallet” using WebAuthn passkeys and OAuth to fetch an encrypted backup blob. No mnemonic is shown.

This spec fixes the hybrid signature format, rotation semantics, attestation schema, app flows, contract surfaces, SDK helpers, threat model, and test plan.

---

## 2) Design goals and non-goals

**Goals**

* Strong long-term security with simple invariants.
* Clear, auditable on-chain validation with minimal moving parts.
* EOA + Vault on one device, smooth account switching.
* Users pick cost vs assurance per transaction.
* Seedless onboarding as a first-class option via Passkeys.
* L2-first ergonomics; L1 still possible with warnings.

**Non-goals (v1.3)**

* Contract upgrades through proxy patterns.
* Social recovery and multi-owner controls.
* Multiple PQC schemes. WOTS+ only in v1.3.

---

## 3) System overview

```
+------------------------------+        +----------------------+
| Mobile App (Flutter)         |        | ProverRegistry       |
| - EOA (Seed or Passkey)      |        | - allow-listed provers|
| - WOTS+ schedule mgmt        |        +----------------------+
| - On-device prover (WOTS)    |
| - EIP-712 attester key       |        +----------------------+
| - OAuth fetch of encPriv     |<------>| OAuth IdP / Cloud    |
+---------------+--------------+        | - stores encrypted   |
                |                       |   ECDSA blob only    |
                v                       +----------------------+
+------------------------------+        +----------------------+
| PQC Vault (ERC-4337 account) |<------>| Factory (CREATE2)    |
| - validateUserOp()           |        +----------------------+
| - ECDSA always on-chain      |
| - PQC: on-chain OR attested  |        +----------------------+
| - Rotation & nonce           |<------>| EntryPoint (4337)    |
+------------------------------+        +----------------------+
```

---

## 4) On-chain protocol

### 4.1 Storage layout

```solidity
struct PQCState {
  address owner;               // ECDSA owner (EOA)
  bytes32 currentCommit;       // keccak256(current WOTS pk bytes)
  bytes32 nextCommit;          // keccak256(next WOTS pk bytes)
  bool    forceOnChainVerify;  // incident switch
  uint64  nextExpectedIndex;   // monotonic WOTS index == nonce
  mapping(uint64 => bool) used;// reserved for sparse mode
  address proverRegistry;      // allow-list registry
}
```

### 4.2 Public interface

```solidity
interface IPQCVault {
  function owner() external view returns (address);
  function currentCommit() external view returns (bytes32);
  function nextCommit() external view returns (bytes32);
  function forceOnChainVerify() external view returns (bool);
  function setForceOnChainVerify(bool on) external;

  function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
  ) external returns (uint256 validationData);
}
```

### 4.3 Hybrid signature packing (locked)

Total **4417 bytes** in this order:

```
ecdsaSig[65] || wotsSig[2144] || wotsPk[2144] || confirmNextCommit[32] || proposeNextCommit[32]
```

* `nonce == wotsIndex` and is monotonic in v1.3.

### 4.4 Validation flow

**Common first step**

1. Verify **ECDSA** on-chain against `owner`. If this fails, revert early.

**Path A — on-chain PQC**
2) Decode `wotsSig, wotsPk`.
3) Require `keccak256(wotsPk) == currentCommit`.
4) Verify WOTS+ on-chain for `wotsIndex`.
5) Require `confirmNextCommit == nextCommit`.
6) Rotate: `currentCommit = nextCommit; nextCommit = proposeNextCommit`.
7) Require `nonce == nextExpectedIndex`; then `nextExpectedIndex++`.

**Path B — attested**
2) Read `aggregatorData = abi.encode(prover, expiresAt, sig65)`.
3) Require `forceOnChainVerify == false`.
4) Require `expiresAt >= block.timestamp` and `prover` allow-listed in `ProverRegistry`.
5) Compute `pqcSigDigest = keccak256(abi.encodePacked(wotsSig, wotsPk))`.
6) Build EIP-712 **Attest** struct (see 4.5). Recover `sig65`, require signer == `prover`.
7) Require field bindings match: `{userOpHash, wallet, entryPoint, chainId, currentCommit, confirmNextCommit, proposeNextCommit, pqcSigDigest}`.
8) Skip WOTS verify; perform the same rotation and nonce update as Path A.

**Force switch**

* If `forceOnChainVerify == true`, Path B is disabled globally.

**Return**

* `validationData` per ERC-4337. In attested flow, `expiresAt` may be encoded in the signature expiry mask.

### 4.5 EIP-712 attestation

**Domain**

```
{name: "EqualFiPQCProver", version: "1"}
```

**Struct**

```
Attest {
  bytes32 userOpHash;
  address wallet;
  address entryPoint;
  uint256 chainId;
  bytes32 pqcSigDigest;        // keccak256(wotsSig || wotsPk)
  bytes32 currentPkCommit;     // == currentCommit
  bytes32 confirmNextCommit;   // == nextCommit
  bytes32 proposeNextCommit;   // next staged value
  uint64  expiresAt;           // >= block.timestamp
  address prover;              // attester signer
}
```

**On-chain payload**

```
aggregatorData = abi.encode(prover:address, expiresAt:uint64, sig65:bytes)
```

### 4.6 Events and errors

**Events**

* `OwnerChanged(address indexed oldOwner, address indexed newOwner)`
* `PQCCommitsRotated(bytes32 currentCommit, bytes32 nextCommit, bytes32 proposedNext)`
* `ProverAttestationUsed(address indexed prover, uint64 expiresAt, bytes32 pqcSigDigest)`
* `ForceOnChainVerifyToggled(bool newValue)`

**Errors**

* `InvalidECDSASignature()`
* `InvalidPQCSignature()`
* `InvalidCommitConfirmation()`
* `NonceMismatch(uint64 expected, uint64 got)`
* `AttestationExpired()`
* `ProverNotAllowed(address prover)`
* `DigestMismatch()`

---

## 5) Cryptography details

* **ECDSA**: secp256k1. Always verified on-chain.
* **WOTS+**: fixed parameterization that yields **2144-byte** signature and **2144-byte** public key. Indices are one-time. The wallet binds `nonce == wotsIndex`.
* **Commitments**: `bytes32 commit = keccak256(wotsPkBytes)` with canonical encoding of the WOTS public key.
* **Hybrid signature**: single contiguous 4417-byte blob, order fixed as in 4.3.
* **Attested digest**: `pqcSigDigest = keccak256(abi.encodePacked(wotsSig, wotsPk))`. Locked for v1.3.

---

## 6) Mobile application design

### 6.1 Custody modes

**Seed Mode**

* Generate mnemonic and ECDSA key.
* Encrypted local storage; explicit backup flow for the mnemonic.
* Biometric gate for usage.

**Passkey Mode (Invisible Wallet)**

* Create a WebAuthn **passkey** for EqualFi RP ID.
* Generate ECDSA key; never show a mnemonic.
* Derive a KEK using a passkey-gated envelope or PAKE-like protocol.
* Wrap the ECDSA private key into `encPriv = AEAD_Encrypt(ecdsaPriv, KEK)`.
* Authenticate with OAuth and upload only `encPriv` and non-sensitive metadata.
* IdP never receives raw keys and cannot unwrap `encPriv`.

**Recovery in Passkey Mode**

* New device: OAuth sign-in → fetch `encPriv` → WebAuthn assert → derive KEK → decrypt `encPriv` → reinstall ECDSA key into device keystore. No mnemonic involved.

### 6.2 PQC Vault lifecycle

1. **Offer Vault** after EOA ready.
2. Generate WOTS+ schedule locally: stage `currentPk` and `nextPk`.
3. Compute commits and **deploy via Factory** with `{owner, currentCommit, nextCommit, registry}`.
4. Show **two accounts** in UI: EOA and Vault.

### 6.3 Sending with the Vault

* Build `UserOperation` with `nonce = wotsIndex`.
* Pack **4417-byte** hybrid signature in the fixed order.
* Security Mode toggle:

  * **Most secure**: no `aggregatorData` → on-chain PQC verify.
  * **Attested**: attach attestation. Show prover identity and expiry.
* Journal the pending op to prevent index reuse after crashes.

### 6.4 Rotation hygiene

* Show current index and indices remaining.
* “Stage new next key” to replenish `nextPk`.
* Warn if headroom is low.

### 6.5 L1 vs L2

* Default to Base or other L2.
* On L1, show explicit gas warnings for on-chain PQC verify. Offer Attested mode as a cheaper option.

---

## 7) SDK surfaces

### 7.1 TypeScript helpers

```ts
import { concat, hexlify } from "ethers";

type HybridSig = {
  ecdsa65: Uint8Array;         // 65 bytes
  wotsSig: Uint8Array;         // 2144 bytes
  wotsPk:  Uint8Array;         // 2144 bytes
  confirmNextCommit: `0x${string}`; // 32-byte hex
  proposeNextCommit: `0x${string}`; // 32-byte hex
};

export function packHybridSignature(h: HybridSig): `0x${string}` {
  if (h.ecdsa65.length !== 65) throw new Error("ecdsa65 length");
  if (h.wotsSig.length !== 2144) throw new Error("wotsSig length");
  if (h.wotsPk.length  !== 2144) throw new Error("wotsPk length");
  const conf = toBytes32(h.confirmNextCommit);
  const prop = toBytes32(h.proposeNextCommit);
  const payload = concat([h.ecdsa65, h.wotsSig, h.wotsPk, conf, prop]);
  if (payload.length !== 4417) throw new Error("hybrid length != 4417");
  return hexlify(payload) as `0x${string}`;
}

function toBytes32(x: `0x${string}`): Uint8Array {
  if (!/^0x[0-9a-fA-F]{64}$/.test(x)) throw new Error("bytes32 hex required");
  return Uint8Array.from(Buffer.from(x.slice(2), "hex"));
}
```

### 7.2 Attestation encoder

```ts
export const DOMAIN = { name: "EqualFiPQCProver", version: "1" } as const;

export const ATTEST_TYPES = {
  Attest: [
    { name: "userOpHash",        type: "bytes32" },
    { name: "wallet",            type: "address" },
    { name: "entryPoint",        type: "address" },
    { name: "chainId",           type: "uint256" },
    { name: "pqcSigDigest",      type: "bytes32" },
    { name: "currentPkCommit",   type: "bytes32" },
    { name: "confirmNextCommit", type: "bytes32" },
    { name: "proposeNextCommit", type: "bytes32" },
    { name: "expiresAt",         type: "uint64"  },
    { name: "prover",            type: "address" },
  ],
} as const;

// signer._signTypedData(DOMAIN, ATTEST_TYPES, message)
```

### 7.3 Digest helper

```ts
import { keccak256, hexlify } from "ethers";

export function pqcSigDigest(wotsSig: Uint8Array, wotsPk: Uint8Array): `0x${string}` {
  return keccak256(hexlify(new Uint8Array([...wotsSig, ...wotsPk]))) as `0x${string}`;
}
```

---

## 8) Components and contracts

### 8.1 PQC Vault

* Implements 4.2.
* Emits events in 4.6.
* Houses `forceOnChainVerify` and `nextExpectedIndex`.

### 8.2 ProverRegistry

Minimal allow-list with owner-only `set(address,bool)`. Emitted `ProverUpdated(prover, allowed)`.

### 8.3 Factory

`deploy(owner, currentCommit, nextCommit, registry) -> address` using CREATE2. Salt derived from `{owner, currentCommit, nextCommit}` for reproducible addresses.

### 8.4 Optional paymaster (future)

Verifying paymaster that subsidizes gas for attested mode by re-verifying EIP-712 off-chain and enforcing policy.

---

## 9) Gas, size, and performance

* **Hybrid payload**: 4417 bytes per op.
* **On-chain WOTS verify**: order-of-magnitude **multi-million** gas per validation. On L2 this is typically inexpensive; on L1 it is costly.
* **Attested**: near ECDSA-only validation cost plus EIP-712 recover and registry lookup.
* **Monotonic nonce** keeps state access simple and predictable.

---

## 10) Security model and threat analysis

### 10.1 Invariants

1. ECDSA owner verification is mandatory.
2. `nonce == wotsIndex`. Reuse is rejected.
3. Rotation is atomic and forward-only: `require(confirmNext == nextCommit)`, then `current = next; next = propose`.
4. Attested mode requires an allow-listed `prover`, unexpired `expiresAt`, and field bindings to wallet, chain, entry point, and PQC digest.
5. `forceOnChainVerify` disables attested verification globally.

### 10.2 Threats and mitigations

* **Replay across chains or wallets**: Attest includes `userOpHash`, `wallet`, `entryPoint`, `chainId`.
* **Rollback of PQC state**: confirmed commit gate plus atomic rotation.
* **Attester compromise**: owner can revoke in `ProverRegistry` and toggle `forceOnChainVerify`. Short `expiresAt` windows.
* **Seed exfiltration**: encrypted storage, backup guidance, biometric gates.
* **Passkey and OAuth risks**: IdP never stores or sees raw keys. `encPriv` is useless without passkey-derived KEK and on-device assertion bound to RP ID.
* **Availability**: on-chain PQC path ensures liveness without any external service.

---

## 11) User experience

* **EOA tab**: balances, send, receive, funding.
* **Vault tab**: balances, rotation status, WOTS index, “Stage next key,” Security Mode toggle.
* **Security Mode chip**:

  * Most secure — on-chain PQC verify. Shows gas bump and L1 warning.
  * Attested — cheaper. Shows prover name and expiry.
* **Errors** are explained plainly and offer fallback to on-chain verification when appropriate.

---

## 12) Deployment and operations

* **Deploy order**: ProverRegistry → Factory → Vaults.
* **Incident response**:

  1. Toggle `forceOnChainVerify = true`.
  2. Revoke suspect provers in `ProverRegistry`.
  3. Publish an advisory in-app.
* **Rotation drift**: monitor events. If clients fail to stage `nextPk`, warn user and block new sends until staged.

---

## 13) Observability

* Index and display:

  * `PQCCommitsRotated` including the new `nextCommit`.
  * `ProverAttestationUsed` with `prover`, `expiresAt`, and `pqcSigDigest`.
* Optional subgraph entities: Vault, Rotation, Attestation, NonceProgress, Prover.

---

## 14) Testing and acceptance

### 14.1 Unit tests

* ECDSA failure rejects early.
* On-chain PQC path rotates and increments index.
* Attested path accepts valid allow-listed prover and unexpired attestation.
* Negative: expired, not-allowed, digest mismatch, commit mismatch, nonce misuse, force switch ignoring attestation.

### 14.2 Fuzz and invariants

* Random `proposeNextCommit` sequences never enable rollback.
* Reused or out-of-order `wotsIndex` never passes.
* Invariant: after success `current(new) == next(old)` and `next(new) == propose(input)`.

### 14.3 E2E

* **Seed Mode**: backup, restore, send both modes.
* **Passkey Mode**: create, wrap, OAuth fetch, passkey unwrap on new device, send both modes.
* Crash-resilience: journal prevents index reuse after restart.
* L1/L2 warnings behave as designed.

### 14.4 Acceptance criteria

* `forge test -vv` passes with invariants and fuzz.
* Demo on Base testnet:

  1. Deploy Vault, show commits.
  2. Send op in Most secure mode.
  3. Send op in Attested mode with device attester.
  4. Verify events and rotation state after each step.
* Passkey recovery restores control without exposing any mnemonic.

---

## 15) Open configuration

* `forceOnChainVerify` default: `false` on L2, `true` recommended on L1 unless attester is trusted.
* `expiresAt` policy: short lifetime, for example 2 minutes from signing.
* ProverRegistry governance: owner key held by EqualFi Labs at launch with plan for community governance later.

---

## 16) Future work

* Verifying paymaster that prefers attested mode.
* Social recovery and multi-owner policy.
* Alternative PQC schemes behind the same commit and digest interface.
* Optional sparse index mode with a bitmap for parallelism.
* Formal proofs for rotation and replay properties.

---

## 17) Reference sketches

### 17.1 Minimal rotation guard

```solidity
function _rotate(bytes32 confirmNextCommit, bytes32 proposedNext) internal {
  if (confirmNextCommit != state.nextCommit) revert InvalidCommitConfirmation();
  bytes32 prevNext = state.nextCommit;
  state.currentCommit = prevNext;
  state.nextCommit = proposedNext;
  emit PQCCommitsRotated(prevNext, state.nextCommit, proposedNext);
}
```

### 17.2 Attestation checker outline

```solidity
function _checkAttestation(
  bytes32 userOpHash,
  bytes32 currentCommit,
  bytes32 nextCommit,
  bytes memory wotsSig,
  bytes memory wotsPk,
  bytes memory aggregatorData
) internal view returns (bool) {
  (address prover, uint64 exp, bytes memory sig65) =
      abi.decode(aggregatorData, (address, uint64, bytes));
  if (state.forceOnChainVerify) return false;
  if (exp < block.timestamp) revert AttestationExpired();
  if (!ProverRegistry(state.proverRegistry).isAllowed(prover)) revert ProverNotAllowed(prover);

  bytes32 digest = keccak256(bytes.concat(wotsSig, wotsPk));
  // build EIP-712 typed data hash for Attest{...} and recover signer
  address rec = /* ECDSA.recover(hash, sig65) */;
  if (rec != prover) revert InvalidECDSASignature();

  // check field bindings match current state and args...
  return true;
}
```

---

## 18) State machine diagram

```
             +-------------------+
   start --> | EOA_READY         |
             +---------+---------+
                       |
         Offer PQC Vault accepted
                       v
             +-------------------+      Stage nextPk low
             | VAULT_DEPLOYED    |------------------+
             | current,next set  |                  |
             +---------+---------+                  |
                       |                            |
       Send op (choose mode)                        |
        |             |                             |
        |             |                             v
        |   +---------v----------+         +--------------------+
        |   | MOST SECURE        |         | STAGE_NEXT_PENDING |
        |   | on-chain WOTS verify         +--------------------+
        |   +---------+----------+
        |             |
        |             v
        |   +---------+----------+
        |   | ROTATE & INCREMENT |
        |   +---------+----------+
        |             |
        |             v
        |   +---------+----------+
        |   | READY FOR NEXT OP  |
        |   +--------------------+
        |
        |   +--------------------+
        +-> | ATTESTED (cheaper) |
            | check EIP-712, reg |
            +---------+----------+
                      |
                      v
              (same ROTATE & INCREMENT)
```

---

## 19) Summary

* Two accounts on one device: EOA for daily use, PQC Vault for long-term security.
* Users choose Seed or Passkey custody at creation.
* Every Vault action can be Most secure with on-chain PQC, or Attested and cheaper with an allow-listed prover.
* Invariants are simple: ECDSA always, nonce equals WOTS index, atomic forward-only rotation, fixed 4417-byte signature, and an incident switch to force on-chain verification.

If you want this as a `SPEC.md` plus starter contracts and a tiny TS SDK folder, I can drop a repo-ready pack next.
