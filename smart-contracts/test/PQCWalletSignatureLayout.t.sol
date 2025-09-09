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

contract PQCWalletSignatureLayoutTest is Test {
    function test_SignatureLayout_Locked() public {
        DummyEntryPoint ep = new DummyEntryPoint();
        PQCWallet wallet = new PQCWallet(IEntryPoint(address(ep)), address(0x1), bytes32(0), bytes32(0));
        assertEq(wallet.SIG_LEN(), 4417);
        assertEq(wallet.ECDSA_OFF(), 0);
        assertEq(wallet.WOTS_SIG_OFF(), 65);
        assertEq(wallet.WOTS_PK_OFF(), 2209);
        assertEq(wallet.CONFIRM_OFF(), 4353);
        assertEq(wallet.PROPOSE_OFF(), 4385);
        assertEq(wallet.PROPOSE_OFF() + 32, wallet.SIG_LEN());
    }
}
