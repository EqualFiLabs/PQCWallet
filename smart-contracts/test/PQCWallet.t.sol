// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";
import {PQCWallet} from "../contracts/PQCWallet.sol";
import {WOTS} from "../contracts/libs/WOTS.sol";

contract DummyEntryPoint is IEntryPoint {
    mapping(address => uint256) public balances;

    function getUserOpHash(UserOperation calldata userOp) external pure returns (bytes32) {
        return keccak256(abi.encode(userOp.sender, userOp.nonce, keccak256(userOp.callData)));
    }

    function depositTo(address account) external payable {
        balances[account] += msg.value;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function withdrawTo(address payable, uint256 amount) external {
        balances[msg.sender] -= amount;
    }
}

contract Target {
    uint256 public x;

    function setX(uint256 v) external {
        x = v;
    }
}

contract PQCWalletTest is Test {
    using WOTS for bytes32;

    event WOTSCommitmentsUpdated(bytes32 currentCommit, bytes32 nextCommit);
    event AggregatorUpdated(address indexed aggregator);
    event VerifierUpdated(address indexed verifier);
    event ForceOnChainVerifySet(bool enabled);

    DummyEntryPoint ep;
    PQCWallet wallet;
    Target target;

    address owner;
    uint256 ownerPk;
    bytes32[67] sk;
    bytes32[67] pk;

    function setUp() public {
        ep = new DummyEntryPoint();
        target = new Target();
        (owner, ownerPk) = makeAddrAndKey("owner");

        bytes32 seed = keccak256("seed");
        (sk, pk) = WOTS.keygen(seed);
        bytes32 commit = WOTS.commitPK(pk);

        wallet = new PQCWallet(IEntryPoint(address(ep)), owner, commit, keccak256("confirm"));
    }

    function test_deposit_and_balanceOfEntryPoint() public {
        assertEq(wallet.balanceOfEntryPoint(), 0);
        vm.deal(address(this), 1 ether);
        wallet.depositToEntryPoint{value: 1 ether}();
        assertEq(wallet.balanceOfEntryPoint(), 1 ether);
        assertEq(ep.balanceOf(address(wallet)), 1 ether);
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

    function test_getAggregator_default_zero() public {
        assertTrue(wallet.forceOnChainVerify());
        assertEq(wallet.getAggregator(), address(0));
    }

    function test_setters_and_getAggregator() public {
        address agg = address(0x1234);
        address ver = address(0x5678);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(wallet));
        emit AggregatorUpdated(agg);
        wallet.setAggregator(agg);
        assertEq(wallet.aggregator(), agg);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(wallet));
        emit VerifierUpdated(ver);
        wallet.setVerifier(ver);
        assertEq(wallet.verifier(), ver);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(wallet));
        emit ForceOnChainVerifySet(false);
        wallet.setForceOnChainVerify(false);
        assertFalse(wallet.forceOnChainVerify());
        assertEq(wallet.getAggregator(), agg);
    }

    function test_setters_only_owner() public {
        vm.prank(address(0xdead));
        vm.expectRevert(PQCWallet.NotOwner.selector);
        wallet.setAggregator(address(1));

        vm.prank(address(0xdead));
        vm.expectRevert(PQCWallet.NotOwner.selector);
        wallet.setVerifier(address(2));

        vm.prank(address(0xdead));
        vm.expectRevert(PQCWallet.NotOwner.selector);
        wallet.setForceOnChainVerify(false);
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
        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);
        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.expectEmit(false, false, false, true, address(wallet));
        emit WOTSCommitmentsUpdated(confirmNext, proposeNext);
        vm.prank(address(ep));
        wallet.validateUserOp(op, userOpHash, 0);

        assertEq(wallet.currentPkCommit(), confirmNext);
        assertEq(wallet.nextPkCommit(), proposeNext);
        assertEq(wallet.nonce(), 1);

        vm.prank(address(ep));
        wallet.execute(address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42));

        assertEq(target.x(), 42);
        assertEq(wallet.nonce(), 1);
    }

    function test_nonce_mismatch_reverts_and_nonce_unchanged() public {
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce() + 1;
        op.callData = abi.encodeWithSelector(
            PQCWallet.execute.selector, address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42)
        );

        bytes32 userOpHash = ep.getUserOpHash(op);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);
        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.prank(address(ep));
        vm.expectRevert(PQCWallet.Nonce_Invalid.selector);
        wallet.validateUserOp(op, userOpHash, 0);

        assertEq(wallet.nonce(), 0);
    }

    function test_confirm_mismatch_reverts() public {
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce();
        op.callData = abi.encodeWithSelector(
            PQCWallet.execute.selector, address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42)
        );

        bytes32 userOpHash = ep.getUserOpHash(op);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);

        bytes32 confirmNext = keccak256("wrong");
        bytes32 proposeNext = keccak256("next");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.prank(address(ep));
        vm.expectRevert(PQCWallet.NextCommit_ConfirmMismatch.selector);
        wallet.validateUserOp(op, userOpHash, 0);
    }

    function test_reverts_on_bad_ecdsa_with_valid_wots() public {
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce();
        op.callData = abi.encodeWithSelector(
            PQCWallet.execute.selector, address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42)
        );

        bytes32 userOpHash = ep.getUserOpHash(op);

        (address other, uint256 otherPk) = makeAddrAndKey("other");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        bytes32[67] memory sig = WOTS.sign(userOpHash, sk);
        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next");
        op.signature = _packSig(eSig, sig, pk, confirmNext, proposeNext);

        vm.prank(address(ep));
        vm.expectRevert(PQCWallet.ECDSA_Invalid.selector);
        wallet.validateUserOp(op, userOpHash, 0);
    }

    function test_reverts_on_bad_ecdsa_even_with_bad_wots() public {
        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.nonce = wallet.nonce();
        op.callData = abi.encodeWithSelector(
            PQCWallet.execute.selector, address(target), 0, abi.encodeWithSelector(Target.setX.selector, 42)
        );

        bytes32 userOpHash = ep.getUserOpHash(op);

        (address other, uint256 otherPk) = makeAddrAndKey("other2");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPk, userOpHash);
        bytes memory eSig = abi.encodePacked(r, s, v);

        bytes32[67] memory badSig;
        bytes32[67] memory badPk;
        bytes32 confirmNext = keccak256("confirm");
        bytes32 proposeNext = keccak256("next");
        op.signature = _packSig(eSig, badSig, badPk, confirmNext, proposeNext);

        vm.prank(address(ep));
        vm.expectRevert(PQCWallet.ECDSA_Invalid.selector);
        wallet.validateUserOp(op, userOpHash, 0);
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
