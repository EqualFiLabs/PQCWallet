// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {WOTS} from "./libs/WOTS.sol";

/// @title PQCWallet: ERC-4337 smart account (Hybrid ECDSA + WOTS)
/// @notice Enforces ECDSA (owner) + WOTS (w=16) per UserOp; rotates WOTS pk each tx.
///         Includes execute() and executeBatch() to support Permit->Action in one op.
contract PQCWallet {
    using WOTS for bytes32;

    error BadECDSA();

    IEntryPoint public immutable entryPoint;
    address public immutable owner;

    bytes32 public currentPkCommit; // commit of current WOTS pk
    bytes32 public nextPkCommit; // optional pre-staged next commit (owner can set)

    /// @notice ERC-4337 nonce; also the WOTS index source.
    uint256 public nonce;

    address public aggregator;
    address public verifier;
    bool public forceOnChainVerify = true;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    event WOTSCommitmentsUpdated(bytes32 currentCommit, bytes32 nextCommit);
    event Executed(address target, uint256 value, bytes data);
    event ExecutedBatch(uint256 calls);
    event AggregatorUpdated(address indexed aggregator);
    event VerifierUpdated(address indexed verifier);
    event ForceOnChainSet(bool enabled);

    modifier onlyEntryPoint() {
        require(msg.sender == address(entryPoint), "not entrypoint");
        _;
    }

    /// @notice Deploys the wallet with its EntryPoint, owner, and initial WOTS commitments.
    /// @param _ep Address of the ERC-4337 EntryPoint.
    /// @param _owner ECDSA owner of the wallet.
    /// @param _initialPkCommit Commitment to the initial WOTS public key.
    /// @param _nextPkCommit Optional pre-staged commitment for the next WOTS key.
    constructor(IEntryPoint _ep, address _owner, bytes32 _initialPkCommit, bytes32 _nextPkCommit) {
        require(_owner != address(0), "owner zero");
        entryPoint = _ep;
        owner = _owner;
        currentPkCommit = _initialPkCommit;
        nextPkCommit = _nextPkCommit;
        emit WOTSCommitmentsUpdated(_initialPkCommit, _nextPkCommit);
    }

    /// @notice Return the aggregator if on-chain verify is disabled.
    /// @return Aggregator address or zero when forceOnChainVerify is enabled.
    function getAggregator() external view returns (address) {
        return forceOnChainVerify ? address(0) : aggregator;
    }

    /// @dev 4417-byte signature packing (exact, no placeholders):
    ///   abi.encodePacked(
    ///       ecdsaSig[65],
    ///       wotsSig[67]*32,
    ///       wotsPk[67]*32,
    ///       confirmNextCommit[32],
    ///       proposeNextCommit[32]
    ///   )
    /// @notice Validates a user operation and rotates the WOTS commitment.
    /// @param userOp The user operation to validate.
    /// @param userOpHash Hash of the user operation.
    /// @param /*missingAccountFunds*/ Ignored funds parameter required by EntryPoint.
    /// @return validationData Zero on success, otherwise packed validation data.
    function validateUserOp(
        IEntryPoint.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 /*missingAccountFunds*/
    ) external onlyEntryPoint returns (uint256 validationData) {
        bytes calldata sig = userOp.signature;
        require(sig.length == 4417, "sig length");

        bytes memory ecdsaSig = new bytes(65);
        bytes32[67] memory wotsSig;
        bytes32[67] memory wotsPk;
        bytes32 confirmNextCommit;
        bytes32 proposeNextCommit;

        // slither-disable-next-line assembly
        assembly {
            calldatacopy(add(ecdsaSig, 0x20), sig.offset, 65)
            let wotsSigPtr := add(sig.offset, 65)
            calldatacopy(wotsSig, wotsSigPtr, mul(32, 67))
            let wotsPkPtr := add(wotsSigPtr, mul(32, 67))
            calldatacopy(wotsPk, wotsPkPtr, mul(32, 67))
            let confirmPtr := add(wotsPkPtr, mul(32, 67))
            confirmNextCommit := calldataload(confirmPtr)
            let proposePtr := add(confirmPtr, 32)
            proposeNextCommit := calldataload(proposePtr)
        }

        // ECDSA verification
        address recovered = _recover(userOpHash, ecdsaSig);
        if (recovered != owner) revert BadECDSA();

        // WOTS commitment check
        bytes32 computedCommit = WOTS.commitPK(wotsPk);
        require(computedCommit == currentPkCommit, "WOTS pk mismatch");

        // WOTS verification
        require(WOTS.verify(userOpHash, wotsSig, wotsPk), "bad WOTS");

        // One-time rotation
        require(confirmNextCommit == nextPkCommit, "confirmNextCommit mismatch");
        currentPkCommit = nextPkCommit;
        nextPkCommit = proposeNextCommit;
        emit WOTSCommitmentsUpdated(currentPkCommit, nextPkCommit);

        // Nonce
        require(userOp.nonce == nonce, "bad nonce");
        nonce++;

        return 0; // valid
    }

    /// @notice Execute a call from the wallet through the EntryPoint.
    /// @param target Destination contract for the call.
    /// @param value ETH value to forward with the call.
    /// @param data Calldata to forward.
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPoint nonReentrant {
        require(target != address(0), "target zero");
        // slither-disable-next-line low-level-calls
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        require(ok, _revertReason(ret));
        emit Executed(target, value, data);
    }

    /// @notice Batch multiple calls (e.g., permit -> transfer) in a single UserOp.
    /// @param targets Destination contracts for each call.
    /// @param values ETH values to forward with each call.
    /// @param datas Calldata for each call.
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas)
        external
        onlyEntryPoint
        nonReentrant
    {
        require(targets.length == values.length && targets.length == datas.length, "len mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            require(targets[i] != address(0), "target zero");
            // slither-disable-next-line calls-loop,low-level-calls
            (bool ok, bytes memory ret) = targets[i].call{value: values[i]}(datas[i]);
            require(ok, _revertReason(ret));
        }
        emit ExecutedBatch(targets.length);
    }

    /// @notice Owner convenience method to pre-stage the next WOTS commitment.
    /// @param nextCommit Commitment to the next WOTS public key.
    function setNextPkCommit(bytes32 nextCommit) external {
        require(msg.sender == owner, "not owner");
        nextPkCommit = nextCommit;
        emit WOTSCommitmentsUpdated(currentPkCommit, nextPkCommit);
    }

    /// @notice Set the aggregator contract used for off-chain validation.
    /// @param _aggregator Address of the aggregator.
    function setAggregator(address _aggregator) external {
        require(msg.sender == owner, "not owner");
        aggregator = _aggregator;
        emit AggregatorUpdated(_aggregator);
    }

    /// @notice Set the verifier contract for aggregated signatures.
    /// @param _verifier Address of the verifier contract.
    function setVerifier(address _verifier) external {
        require(msg.sender == owner, "not owner");
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    /// @notice Enable or disable mandatory on-chain WOTS verification.
    /// @param enabled Whether to force on-chain verification.
    function setForceOnChainVerify(bool enabled) external {
        require(msg.sender == owner, "not owner");
        forceOnChainVerify = enabled;
        emit ForceOnChainSet(enabled);
    }

    /// @notice Receive plain ETH transfers.
    receive() external payable {}

    /// @notice Deposit ETH to the EntryPoint on behalf of this wallet.
    function depositToEntryPoint() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    // --------- internal helpers ----------
    function _recover(bytes32 digest, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "ecdsa len");
        bytes32 r;
        bytes32 s;
        uint8 v;
        // slither-disable-next-line assembly
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
        // slither-disable-next-line assembly
        assembly {
            ret := add(ret, 0x04)
        }
        return abi.decode(ret, (string));
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "reentrant");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}
