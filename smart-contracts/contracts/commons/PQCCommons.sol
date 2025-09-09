// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PQC Digest & Rotation Semantics (Authoritative)
 * @notice
 * * The wallet verifies the WOTS+ signature over the canonical AA digest `userOpHash`.
 * * The off-chain aggregator produces an EIP-712 `Attest` that includes:
 * ```
 * `pqcSigDigest = keccak256(wotsSig || wotsPk || confirmNextCommit || proposeNextCommit)`
 * ```
 * as supplementary evidence for post-quantum verification and auditing.
 * * Key rotation is atomic: upon successful validation, `current = next` and `next = propose`.
 * The wallet nonce equals the WOTS index.
 */
library PQCCommons {}
