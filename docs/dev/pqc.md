# PQC

## WOTS commit parity

`WOTS.commitPK` (Solidity) and `Wots.commitPk` (Dart) both hash a full WOTS
public key by concatenating its 67 `bytes32` elements and applying `SHA-256`.

A fixed public key vector where `pk[i] = bytes32(i)` produces the commitment
`0x765d90c3c681035923f5df7760cedea68ebd2d977fc22a3752839104c6b33176` in both
implementations, as enforced by unit tests.
