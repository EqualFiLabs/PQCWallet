// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";
import {PQCWallet} from "../contracts/PQCWallet.sol";
import {WOTS} from "../contracts/libs/WOTS.sol";

contract Deploy is Script {
    using WOTS for bytes32;

    // Set to Base Sepolia EntryPoint for testing or Base mainnet for prod
    address constant ENTRYPOINT = 0x0000000000000000000000000000000000000000; // replace on deploy

    function run() external {
        vm.startBroadcast();

        // Demo seed → WOTS
        bytes32 seed = keccak256("equalfi-demo-seed");
        (bytes32[67] memory sk, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32 commit = WOTS.commitPK(pk);
        bytes32 nextCommit = keccak256("next-commit-demo");

        // Owner is the deployer by default
        address owner = msg.sender;

        PQCWallet wallet = new PQCWallet(
            IEntryPoint(ENTRYPOINT),
            owner,
            commit,
            nextCommit
        );

        console2.log("PQCWallet at", address(wallet));
        vm.stopBroadcast();
    }
}
