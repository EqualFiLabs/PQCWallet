// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title WOTS (Winternitz One-Time Signature) helpers (w=16; hash-only)
/// @notice PQ-conservative, EVM-friendly (sha256). Used for Track A1.
///         Public key = 67 * 32B; Signature = 67 * 32B; Message digest = 32B.
library WOTS {
    uint256 internal constant N = 32;     // bytes per element
    uint256 internal constant W = 16;     // winternitz parameter
    uint256 internal constant L1 = 64;    // 256 bits / log2(16)
    uint256 internal constant L2 = 3;     // ceil(log_16(960)) = 3
    uint256 constant L  = L1 + L2;

    function messageDigits(bytes32 msgHash) internal pure returns (uint8[L] memory digits) {
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(msgHash[i]);
            digits[2*i]   = b >> 4;
            digits[2*i+1] = b & 0x0f;
        }
        uint256 csum = 0;
        for (uint256 i = 0; i < L1; i++) csum += (W - 1) - digits[i];
        digits[L1]   = uint8((csum >> 8) & 0x0f);
        digits[L1+1] = uint8((csum >> 4) & 0x0f);
        digits[L1+2] = uint8( csum       & 0x0f);
        return digits;
    }

    function _F(bytes32 x) private pure returns (bytes32) {
        return sha256(abi.encodePacked(x));
    }

    function verify(bytes32 msgHash, bytes32[L] memory sig, bytes32[L] memory pk) internal pure returns (bool) {
        uint8[L] memory d = messageDigits(msgHash);
        for (uint256 i = 0; i < L; i++) {
            uint256 steps = (W - 1) - d[i];
            bytes32 v = sig[i];
            for (uint256 j = 0; j < steps; j++) {
                v = _F(v);
            }
            if (v != pk[i]) return false;
        }
        return true;
    }

    function commitPK(bytes32[L] memory pk) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pk));
    }

    // ---------- Deterministic helpers for local tests/demos ----------
    function keygen(bytes32 seed) internal pure returns (bytes32[L] memory sk, bytes32[L] memory pk) {
        unchecked {
            for (uint256 i = 0; i < L; i++) {
                sk[i] = keccak256(abi.encodePacked(seed, uint32(i)));
                bytes32 v = sk[i];
                for (uint256 j = 0; j < W - 1; j++) v = _F(v);
                pk[i] = v;
            }
        }
    }

    function sign(bytes32 msgHash, bytes32[L] memory sk) internal pure returns (bytes32[L] memory sig) {
        uint8[L] memory d = messageDigits(msgHash);
        for (uint256 i = 0; i < L; i++) {
            uint256 steps = d[i];
            bytes32 v = sk[i];
            for (uint256 j = 0; j < steps; j++) v = _F(v);
            sig[i] = v;
        }
    }
}
