// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IWalletAggregator} from "../../contracts/interfaces/IWalletAggregator.sol";
import {IEntryPoint} from "../../contracts/interfaces/IEntryPoint.sol";

/// @notice Mock aggregator that reverts on any call to signal usage in tests.
contract MockAggregator is IWalletAggregator {
    error MockAggregatorWasCalled();

    function validateUserOp(
        IEntryPoint.UserOperation calldata,
        bytes32
    ) external pure override {
        revert MockAggregatorWasCalled();
    }
}

