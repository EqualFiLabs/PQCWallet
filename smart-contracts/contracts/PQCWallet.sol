// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {WOTS} from "./libs/WOTS.sol";

/// @title PQCWallet: ERC-4337 smart account (Hybrid ECDSA + WOTS)
/// @notice Enforces ECDSA (owner) + WOTS (w=16) per UserOp; rotates WOTS pk each tx.
///         Includes execute() and executeBatch() to support Permit->Action in one op.
contract PQCWallet {
    using WOTS for bytes32;

    IEntryPoint public immutable entryPoint;
    address public immutable owner;

    bytes32 public currentPkCommit; // commit of current WOTS pk
    bytes32 public nextPkCommit;    // optional pre-staged next commit (owner can set)

    uint256 public nonce; // AA nonce; mirrors WOTS index

    event WOTSCommitmentsUpdated(bytes32 currentCommit, bytes32 nextCommit);
    event Executed(address target, uint256 value, bytes data);
    event ExecutedBatch(uint256 calls);

    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "not entrypoint");
        _;
    }

    constructor(IEntryPoint _ep, address _owner, bytes32 _initialPkCommit, bytes32 _nextPkCommit) {
        entryPoint = _ep;
        owner = _owner;
        currentPkCommit = _initialPkCommit;
        nextPkCommit = _nextPkCommit;
        emit WOTSCommitmentsUpdated(_initialPkCommit, _nextPkCommit);
    }

    /// @dev Signature packing (exact, no placeholders):
    ///   abi.encodePacked(
    ///       ecdsaSig[65],
    ///       wotsSig[67]*32,
    ///       wotsPk[67]*32,
    ///       nextPkCommit[32]
    ///   )
    function validateUserOp(
        IEntryPoint.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 /*missingAccountFunds*/
    ) external onlyEntryPoint returns (uint256 validationData) {
        bytes calldata sig = userOp.signature;
        require(sig.length == (65 + (32 * 67) + (32 * 67) + 32), "bad sig length");

        bytes memory ecdsaSig = new bytes(65);
        bytes32[67] memory wotsSig;
        bytes32[67] memory wotsPk;
        bytes32 providedNextCommit;

        assembly {
            calldatacopy(add(ecdsaSig, 0x20), sig.offset, 65)
            let wotsSigPtr := add(sig.offset, 65)
            calldatacopy(wotsSig, wotsSigPtr, mul(32, 67))
            let wotsPkPtr := add(wotsSigPtr, mul(32, 67))
            calldatacopy(wotsPk, wotsPkPtr, mul(32, 67))
            let nextPtr := add(wotsPkPtr, mul(32, 67))
            providedNextCommit := calldataload(nextPtr)
        }

        // ECDSA verification
        address recovered = _recover(userOpHash, ecdsaSig);
        require(recovered == owner, "bad ECDSA");

        // WOTS commitment check
        bytes32 computedCommit = WOTS.commitPK(wotsPk);
        require(computedCommit == currentPkCommit, "WOTS pk mismatch");

        // WOTS verification
        require(WOTS.verify(userOpHash, wotsSig, wotsPk), "bad WOTS");

        // One-time rotation
        require(providedNextCommit != bytes32(0), "next commit required");
        currentPkCommit = providedNextCommit;
        nextPkCommit = bytes32(0);
        emit WOTSCommitmentsUpdated(currentPkCommit, nextPkCommit);

        // Nonce
        require(userOp.nonce == nonce, "bad nonce");
        nonce++;

        return 0; // valid
    }

    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPoint {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        require(ok, _revertReason(ret));
        emit Executed(target, value, data);
    }

    /// @notice Batch multiple calls (e.g., permit -> transfer) in a single UserOp.
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external onlyEntryPoint {
        require(targets.length == values.length && targets.length == datas.length, "len mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(datas[i]);
            require(ok, _revertReason(ret));
        }
        emit ExecutedBatch(targets.length);
    }

    // Owner convenience to pre-stage next commitment
    function setNextPkCommit(bytes32 nextCommit) external {
        require(msg.sender == owner, "not owner");
        nextPkCommit = nextCommit;
        emit WOTSCommitmentsUpdated(currentPkCommit, nextPkCommit);
    }

    receive() external payable {}
    function depositToEntryPoint() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    // --------- internal helpers ----------
    function _recover(bytes32 digest, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "ecdsa len");
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "bad v");
        return ecrecover(digest, v, r, s);
    }

    function _revertReason(bytes memory ret) private pure returns (string memory) {
        if (ret.length < 68) return "call failed";
        assembly { ret := add(ret, 0x04) }
        return abi.decode(ret, (string));
    }
}
