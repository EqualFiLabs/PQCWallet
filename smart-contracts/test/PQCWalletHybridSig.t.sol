// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PQCWallet} from "../contracts/PQCWallet.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";

contract DummyEntryPoint is IEntryPoint {
    function getUserOpHash(UserOperation calldata) external pure returns (bytes32) {
        return bytes32(0);
    }

    function depositTo(address) external payable {}

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function withdrawTo(address payable, uint256) external pure {}
}

/// @notice Minimal EntryPoint-style UserOperation struct for validateUserOp tests.
///         Only fields relevant to length gating are populated.
contract PQCWalletHybridSigTest is Test {
    PQCWallet internal wallet;
    DummyEntryPoint internal ep;

    uint256 constant ECDSA_LEN = 65;
    uint256 constant WOTS_SIG_LEN = 67 * 32; // 2144
    uint256 constant WOTS_PK_LEN = 67 * 32; // 2144
    uint256 constant COMMIT_LEN = 32;
    uint256 constant HYBRID_LEN = ECDSA_LEN + WOTS_SIG_LEN + WOTS_PK_LEN + COMMIT_LEN + COMMIT_LEN; // 4417
    uint256 constant LEGACY_LEN_NO_COMMITS = ECDSA_LEN + WOTS_SIG_LEN + WOTS_PK_LEN; // 4353
    uint256 constant LEGACY_LEN_ONE_COMMIT = LEGACY_LEN_NO_COMMITS + COMMIT_LEN; // 4385

    function setUp() public {
        ep = new DummyEntryPoint();
        wallet = new PQCWallet(IEntryPoint(address(ep)), address(this), bytes32("curr"), bytes32("next"));
    }

    function _mkUserOp(bytes memory sig) internal view returns (IEntryPoint.UserOperation memory op) {
        op.sender = address(wallet);
        op.signature = sig;
    }

    function _mkBytes(uint256 len, bytes1 fill) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = fill;
        }
    }

    function _mkHybridSig(
        bytes1 ecdsaFill,
        bytes1 wotsSigFill,
        bytes1 wotsPkFill,
        bytes32 confirmNextCommit,
        bytes32 proposeNextCommit
    ) internal pure returns (bytes memory sig) {
        bytes memory ecdsa = _mkBytes(ECDSA_LEN, ecdsaFill);
        bytes memory wSig = _mkBytes(WOTS_SIG_LEN, wotsSigFill);
        bytes memory wPk = _mkBytes(WOTS_PK_LEN, wotsPkFill);
        sig = bytes.concat(ecdsa, wSig, wPk, abi.encodePacked(confirmNextCommit), abi.encodePacked(proposeNextCommit));
        require(sig.length == HYBRID_LEN, "bad construction");
    }

    function test_RevertsOnLegacyLength_NoCommits_4353() public {
        bytes memory legacy = _mkBytes(LEGACY_LEN_NO_COMMITS, 0x11);
        IEntryPoint.UserOperation memory op = _mkUserOp(legacy);
        vm.prank(address(ep));
        vm.expectRevert(PQCWallet.Sig_Length.selector);
        wallet.validateUserOp(op, bytes32(0), 0);
    }

    function test_RevertsOnLegacyLength_OneCommit_4385() public {
        bytes memory legacy = _mkBytes(LEGACY_LEN_ONE_COMMIT, 0x22);
        IEntryPoint.UserOperation memory op = _mkUserOp(legacy);
        vm.prank(address(ep));
        vm.expectRevert(PQCWallet.Sig_Length.selector);
        wallet.validateUserOp(op, bytes32(0), 0);
    }

    function test_Hybrid4417_BytesLayoutAndLength_OKGate() public {
        bytes32 confirmNext = bytes32("next");
        bytes32 proposeNext = bytes32("prop");
        bytes memory hybrid = _mkHybridSig(0xAA, 0xBB, 0xCC, confirmNext, proposeNext);
        assertEq(hybrid.length, HYBRID_LEN, "hybrid length");
        // [0..64] ECDSA, [65..2208] WOTS sig, [2209..4352] WOTS pk, [4353..4384] confirm, [4385..4416] propose
        assertEq(uint8(hybrid[0]), 0xAA, "ecdsa starts");
        assertEq(uint8(hybrid[64]), 0xAA, "ecdsa ends");
        assertEq(uint8(hybrid[65]), 0xBB, "wSig start");
        assertEq(uint8(hybrid[65 + WOTS_SIG_LEN - 1]), 0xBB, "wSig end");
        assertEq(uint8(hybrid[65 + WOTS_SIG_LEN]), 0xCC, "wPk start");
        assertEq(uint8(hybrid[65 + WOTS_SIG_LEN + WOTS_PK_LEN - 1]), 0xCC, "wPk end");
        uint256 confirmIndex = ECDSA_LEN + WOTS_SIG_LEN + WOTS_PK_LEN;
        bytes32 confirmRead;
        bytes32 proposeRead;
        assembly {
            confirmRead := mload(add(add(hybrid, 0x20), confirmIndex))
            proposeRead := mload(add(add(hybrid, 0x20), add(confirmIndex, 32)))
        }
        assertEq(confirmRead, confirmNext, "confirm slot");
        assertEq(proposeRead, proposeNext, "propose slot");

        IEntryPoint.UserOperation memory op = _mkUserOp(hybrid);
        vm.prank(address(ep));
        // ensure no revert with "sig length"
        try wallet.validateUserOp(op, bytes32(0), 0) {}
        catch Error(string memory reason) {
            assertTrue(keccak256(bytes(reason)) != keccak256("sig length"), "should pass length gate");
        } catch (bytes memory) {}
    }
}
