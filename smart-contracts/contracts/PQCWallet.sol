// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {WOTS} from "./libs/WOTS.sol";

/// @title PQCWallet: ERC-4337 smart account (Hybrid ECDSA + WOTS)
/// @notice Enforces ECDSA (owner) + WOTS (w=16) per UserOp; rotates WOTS pk each tx.
///         Includes execute() and executeBatch() to support Permit->Action in one op.
contract PQCWallet {
    using WOTS for bytes32;

    error ECDSA_Invalid();
    error PQC_CommitMismatch();
    error NextCommit_ConfirmMismatch();
    error Nonce_Invalid();
    error NotOwner();
    error Sig_Length();

    /// @notice Canonical ERC-4337 EntryPoint used by this wallet.
    IEntryPoint public immutable entryPoint;

    /// @notice ECDSA owner controlling the wallet.
    address public immutable owner;

    /// @notice Commitment to the current WOTS public key.
    bytes32 public currentPkCommit;

    /// @notice Optional pre-staged commitment for the next WOTS key.
    bytes32 public nextPkCommit;

    /// @notice ERC-4337 nonce; also the WOTS index source.
    uint256 public nonce;

    /// @notice Aggregator contract used for off-chain validation when enabled.
    address public aggregator;

    /// @notice Verifier contract validating aggregated signatures.
    address public verifier;

    /// @notice Enforces on-chain WOTS verification when true.
    bool public forceOnChainVerify = true;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    uint256 public constant SIG_LEN = 4417;
    uint256 public constant ECDSA_LEN = 65;
    uint256 public constant WOTS_SEG_LEN = 67 * 32; // 2144

    // Parser offsets
    uint256 public constant ECDSA_OFF = 0;
    uint256 public constant WOTS_SIG_OFF = ECDSA_OFF + ECDSA_LEN;
    uint256 public constant WOTS_PK_OFF = WOTS_SIG_OFF + WOTS_SEG_LEN;
    uint256 public constant CONFIRM_OFF = WOTS_PK_OFF + WOTS_SEG_LEN;
    uint256 public constant PROPOSE_OFF = CONFIRM_OFF + 32;

    /// @notice Emitted when WOTS commitments are rotated or staged.
    /// @param currentCommit Commitment to the current WOTS public key.
    /// @param nextCommit Commitment to the next WOTS public key.
    event WOTSCommitmentsUpdated(bytes32 currentCommit, bytes32 nextCommit);

    /// @notice Emitted after a single call is executed.
    /// @param target Destination contract for the call.
    /// @param value ETH value forwarded with the call.
    /// @param data Calldata forwarded.
    event Executed(address target, uint256 value, bytes data);

    /// @notice Emitted after a batch of calls is executed.
    /// @param calls Number of calls executed.
    event ExecutedBatch(uint256 calls);

    /// @notice Emitted when the aggregator is updated.
    /// @param aggregator Address of the new aggregator.
    event AggregatorUpdated(address indexed aggregator);

    /// @notice Emitted when the verifier contract is updated.
    /// @param verifier Address of the new verifier contract.
    event VerifierUpdated(address indexed verifier);

    /// @notice Emitted when on-chain verification requirement changes.
    /// @param enabled Whether on-chain verification is now enforced.
    event ForceOnChainVerifySet(bool enabled);

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

    /**
     * @dev Signature format (strict, 4417 bytes total):
     * ecdsaSig(65) ||
     * wotsSig(67*32 = 2144) ||
     * wotsPk(67*32 = 2144) ||
     * confirmNextCommit(32) ||
     * proposeNextCommit(32)
     *
     * Layout (byte offsets):
     * ECDSA:             [0..64]
     * WOTS sig:          [65..2208]   // 2144 bytes
     * WOTS pk:           [2209..4352] // 2144 bytes
     * confirmNextCommit: [4353..4384] // 32 bytes
     * proposeNextCommit: [4385..4416] // 32 bytes
     *
     * Verification:
     * - WOTS+ is verified over `userOpHash` (canonical AA digest).
     * - On success, rotation is atomic: `current = next`, `next = propose`.
     * - `nonce()` equals the WOTS index.
     *
     * Requirements:
     * - `require(sig.length == 4417, "sig length")`
     *
     * @param userOp User operation.
     * @param userOpHash Hash of the user operation.
     * @return validationData Zero on success, otherwise packed validation data.
     */
    function validateUserOp(
        IEntryPoint.UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 /*missingAccountFunds*/
    ) external onlyEntryPoint returns (uint256 validationData) {
        bytes calldata sig = userOp.signature;
        require(sig.length == SIG_LEN, "sig length");

        bytes memory ecdsaSig = new bytes(ECDSA_LEN);
        bytes32[67] memory wotsSig;
        bytes32[67] memory wotsPk;
        bytes32 confirmNextCommit;
        bytes32 proposeNextCommit;

        // slither-disable-next-line assembly
        assembly {
            calldatacopy(add(ecdsaSig, 0x20), sig.offset, ECDSA_LEN) // ECDSA_OFF = 0
            let wotsSigPtr := add(sig.offset, 65) // WOTS_SIG_OFF
            calldatacopy(wotsSig, wotsSigPtr, WOTS_SEG_LEN)
            let wotsPkPtr := add(sig.offset, 2209) // WOTS_PK_OFF
            calldatacopy(wotsPk, wotsPkPtr, WOTS_SEG_LEN)
            let confirmPtr := add(sig.offset, 4353) // CONFIRM_OFF
            confirmNextCommit := calldataload(confirmPtr)
            let proposePtr := add(sig.offset, 4385) // PROPOSE_OFF
            proposeNextCommit := calldataload(proposePtr)
        }

        // ECDSA verification
        address recovered = _recover(userOpHash, ecdsaSig);
        if (recovered != owner) revert ECDSA_Invalid();

        // WOTS commitment check
        bytes32 computedCommit = WOTS.commitPK(wotsPk);
        if (computedCommit != currentPkCommit) revert PQC_CommitMismatch();

        // WOTS verification
        require(WOTS.verify(userOpHash, wotsSig, wotsPk), "bad WOTS");

        // One-time rotation
        if (confirmNextCommit != nextPkCommit) revert NextCommit_ConfirmMismatch();
        currentPkCommit = nextPkCommit;
        nextPkCommit = proposeNextCommit;
        emit WOTSCommitmentsUpdated(currentPkCommit, nextPkCommit);

        // Nonce
        if (userOp.nonce != nonce) revert Nonce_Invalid();
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
        if (msg.sender != owner) revert NotOwner();
        nextPkCommit = nextCommit;
        emit WOTSCommitmentsUpdated(currentPkCommit, nextPkCommit);
    }

    /// @notice Set the aggregator contract used for off-chain validation.
    /// @param _aggregator Address of the aggregator.
    function setAggregator(address _aggregator) external {
        if (msg.sender != owner) revert NotOwner();
        aggregator = _aggregator;
        emit AggregatorUpdated(_aggregator);
    }

    /// @notice Set the verifier contract for aggregated signatures.
    /// @param _verifier Address of the verifier contract.
    function setVerifier(address _verifier) external {
        if (msg.sender != owner) revert NotOwner();
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    /// @notice Enable or disable mandatory on-chain WOTS verification.
    /// @param enabled Whether to force on-chain verification.
    function setForceOnChainVerify(bool enabled) external {
        if (msg.sender != owner) revert NotOwner();
        forceOnChainVerify = enabled;
        emit ForceOnChainVerifySet(enabled);
    }

    /// @notice Receive plain ETH transfers.
    receive() external payable {}

    /// @notice Deposit ETH to the EntryPoint on behalf of this wallet.
    function depositToEntryPoint() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @notice Get this wallet's deposit in the EntryPoint.
    /// @return amount The current deposit balance held by the EntryPoint.
    function balanceOfEntryPoint() external view returns (uint256 amount) {
        amount = entryPoint.balanceOf(address(this));
    }

    // --------- internal helpers ----------
    function _recover(bytes32 digest, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) revert Sig_Length();
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
        if (v != 27 && v != 28) revert ECDSA_Invalid();
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
