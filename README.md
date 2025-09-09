# PQCWallet

Monorepo for the PQCWallet project, bringing together on-chain smart contracts and a cross-platform mobile app in preparation for post-quantum cryptography.

## Packages

- `smart-contracts` – Solidity contracts built with Foundry.
- `mobile` – Flutter application for iOS and Android.
- `docs` – Project documentation.
- `ops` – Operational scripts and configuration.

## Digest semantics (canonical)

- Wallet verifies WOTS over `userOpHash`.
- Aggregator attests EIP-712 with `pqcSigDigest = keccak256(wotsSig||wotsPk||confirm||propose)`.
- Atomic rotation; `nonce = WOTS index`.

```
sig =
  ecdsaSig[65] ||
  wotsSig[2144] ||       // 67 * 32
  wotsPk[2144]  ||       // 67 * 32
  confirmNextCommit[32] ||
  proposeNextCommit[32]  // total = 4417 bytes
```
