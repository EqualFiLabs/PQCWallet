// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";
import {PQCWallet} from "../contracts/PQCWallet.sol";
import {WOTS} from "../contracts/libs/WOTS.sol";

contract DummyEntryPoint is IEntryPoint {
    function getUserOpHash(UserOperation calldata userOp) external pure returns (bytes32) {
        return keccak256(abi.encode(userOp.sender, userOp.nonce, keccak256(userOp.callData)));
    }

    function depositTo(address) external payable {}

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function withdrawTo(address payable, uint256) external pure {}
}

contract Target {
    uint256 public x;

    function setX(uint256 v) external {
        x = v;
    }
}

contract PQCWalletTest is Test {
    using WOTS for bytes32;

    DummyEntryPoint ep;
    PQCWallet wallet;
    Target target;

    address owner;
    uint256 ownerPk;

    function setUp() public {
        ep = new DummyEntryPoint();
        target = new Target();
        (owner, ownerPk) = makeAddrAndKey("owner");

        bytes32 seed = keccak256("seed");
        (, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32 commit = WOTS.commitPK(pk);

        wallet = new PQCWallet(IEntryPoint(address(ep)), owner, commit, keccak256("confirm"));
    }

    function _packSig(
        bytes memory ecdsaSig,
        bytes32[67] memory wotsSig,
        bytes32[67] memory wotsPk,
        bytes32 confirmNext,
        bytes32 proposeNext
    ) internal pure returns (bytes memory out) {
        out = abi.encodePacked(ecdsaSig);
        for (uint256 i = 0; i < WOTS.L; i++) {
            out = bytes.concat(out, wotsSig[i]);
        }
        for (uint256 i = 0; i < WOTS.L; i++) {
            out = bytes.concat(out, wotsPk[i]);
        }
        out = bytes.concat(out, confirmNext);
        out = bytes.concat(out, proposeNext);
    }

    function test_validate_execute() public {
        // Build op: setX(42)
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce();
        op.callData = abi.encodeWithSelector(
            PQCWallet.execute.selector, address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42)
        );

        bytes32 userOpHash = ep.getUserOpHash(op);

        // ECDSA
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        // WOTS
        bytes32 seed = keccak256("seed");
        (bytes32[67] memory sk, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);
        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.prank(address(ep));
        wallet.validateUserOp(op, userOpHash, 0);

        vm.prank(address(ep));
        wallet.execute(address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42));

        assertEq(target.x(), 42);
        assertEq(wallet.nonce(), 1);
    }

    function test_batch() public {
        // two calls in a batch: setX(1) then setX(2)
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce();

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        targets[0] = address(target);
        targets[1] = address(target);
        datas[0] = abi.encodeWithSelector(Target.setX.selector, 1);
        datas[1] = abi.encodeWithSelector(Target.setX.selector, 2);

        op.callData = abi.encodeWithSelector(PQCWallet.executeBatch.selector, targets, values, datas);

        bytes32 userOpHash = ep.getUserOpHash(op);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        bytes32 seed = keccak256("seed");
        (bytes32[67] memory sk, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);

        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next2");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.prank(address(ep));
        wallet.validateUserOp(op, userOpHash, 0);

        vm.prank(address(ep));
        wallet.executeBatch(targets, values, datas);

        assertEq(target.x(), 2);
        assertEq(wallet.nonce(), 1);
    }

    function test_gas_validateUserOp() public {
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce();
        op.callData = abi.encodeWithSelector(
            PQCWallet.execute.selector, address(target), 0, abi.encodeWithSelector(Target.setX.selector, 1)
        );

        bytes32 userOpHash = ep.getUserOpHash(op);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        bytes32 seed = keccak256("seed");
        (bytes32[67] memory sk, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);
        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next3");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.prank(address(ep));
        wallet.validateUserOp(op, userOpHash, 0);
    }

    function test_gas_execute() public {
        vm.prank(address(ep));
        wallet.execute(address(target), 0, abi.encodeWithSelector(Target.setX.selector, 5));
    }

    function test_gas_executeBatch() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        targets[0] = address(target);
        targets[1] = address(target);
        datas[0] = abi.encodeWithSelector(Target.setX.selector, 7);
        datas[1] = abi.encodeWithSelector(Target.setX.selector, 8);

        vm.prank(address(ep));
        wallet.executeBatch(targets, values, datas);
    }
}
