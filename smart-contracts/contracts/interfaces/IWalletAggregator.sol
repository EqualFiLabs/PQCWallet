// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEntryPoint} from "./IEntryPoint.sol";

/// @notice Minimal interface for an off-chain verifier/aggregator used by PQCWallet.
/// @dev Implementations should revert on invalid user operations.
interface IWalletAggregator {
    /// @notice Validate a user operation via the aggregator.
    /// @param userOp The user operation to validate.
    /// @param userOpHash The hash of the user operation.
    function validateUserOp(IEntryPoint.UserOperation calldata userOp, bytes32 userOpHash) external;
}

