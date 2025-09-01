// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";
import {PQCWallet} from "../contracts/PQCWallet.sol";
import {WOTS} from "../contracts/libs/WOTS.sol";
import {ENTRY_POINT_BASE_MAINNET, ENTRY_POINT_BASE_SEPOLIA} from "../contracts/constants/EntryPoint.sol";

contract Deploy is Script {
    using WOTS for bytes32;

    function run() external {
        vm.startBroadcast();

        address ep;
        if (block.chainid == 8453) {
            ep = ENTRY_POINT_BASE_MAINNET;
        } else if (block.chainid == 84532) {
            ep = ENTRY_POINT_BASE_SEPOLIA;
        } else {
            revert("unsupported chain");
        }

        // Demo seed → WOTS
        bytes32 seed = keccak256("equalfi-demo-seed");
        (bytes32[67] memory sk, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32 commit = WOTS.commitPK(pk);
        bytes32 nextCommit = keccak256("next-commit-demo");

        // Owner is the deployer by default
        address owner = msg.sender;

        PQCWallet wallet = new PQCWallet(
            IEntryPoint(ep),
            owner,
            commit,
            nextCommit
        );

        console2.log("PQCWallet at", address(wallet));
        vm.stopBroadcast();
    }
}
