// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PQCWallet} from "../contracts/PQCWallet.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";

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

contract PQCWallet_AggregatorFlag_Test is Test {
    DummyEntryPoint internal ep;
    PQCWallet internal wallet;
    MockAggregator internal mockAgg;
    address internal owner;

    function setUp() public {
        ep = new DummyEntryPoint();
        owner = makeAddr("owner");
        wallet = new PQCWallet(IEntryPoint(address(ep)), owner, bytes32(0), bytes32(0));
    }

    function test_WhenForceOnChainVerifyEnabled_AggregatorIsDisabled_AndValidateUserOpTakesOnChainPath() public {
        mockAgg = new MockAggregator();

        vm.prank(owner);
        wallet.setAggregator(address(mockAgg));

        vm.prank(owner);
        wallet.setForceOnChainVerify(true);

        assertEq(wallet.getAggregator(), address(0));

        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.signature = hex"00"; // wrong length

        vm.prank(address(ep));
        vm.expectRevert(bytes("sig length"));
        wallet.validateUserOp(op, bytes32(0), 0);
    }

    function test_WhenForceOnChainVerifyDisabled_AggregatorGetterReturnsSentinel_AndPathTouchesAggregator() public {
        mockAgg = new MockAggregator();

        vm.prank(owner);
        wallet.setAggregator(address(mockAgg));

        vm.prank(owner);
        wallet.setForceOnChainVerify(false);

        assertEq(wallet.getAggregator(), address(mockAgg));

        IEntryPoint.UserOperation memory op;
        op.sender = address(wallet);
        op.signature = hex"00"; // wrong length

        vm.prank(address(ep));
        vm.expectRevert(MockAggregator.MockAggregatorWasCalled.selector);
        wallet.validateUserOp(op, bytes32(0), 0);
    }
}

