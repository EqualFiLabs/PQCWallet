// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal subset of ERC-4337 EntryPoint used by PQCWallet.
/// NOTE: This interface matches the parts we call in tests and in production
/// you will wire the real EntryPoint address on Base.
interface IEntryPoint {
    struct UserOperation {
        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
        bytes signature;
    }

    function getUserOpHash(UserOperation calldata userOp) external view returns (bytes32);

    // deposit helpers (not used by tests here, but useful in prod)
    function depositTo(address account) external payable;
    function balanceOf(address account) external view returns (uint256);
    function withdrawTo(address payable withdrawAddress, uint256 amount) external;
}
