# Mobile Attest Helper

## Attest Struct

The wallet builds an EIP-712 `Attest` struct when preparing data for a future aggregator path.

| Field | Type |
| ----- | ---- |
| `userOpHash` | `bytes32` |
| `wallet` | `address` |
| `entryPoint` | `address` |
| `chainId` | `uint256` |
| `pqcSigDigest` | `bytes32` |
| `currentPkCommit` | `bytes32` |
| `confirmNextCommit` | `bytes32` |
| `proposeNextCommit` | `bytes32` |
| `expiresAt` | `uint64` |
| `prover` | `address` |

The EIP-712 domain is fixed to `{name: 'EqualFiPQCProver', version: '1'}`.

Phase-0 computes this hash locally and skips any network calls while the aggregator feature flag remains disabled.
