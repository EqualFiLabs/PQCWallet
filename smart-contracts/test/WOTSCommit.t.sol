// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/libs/WOTS.sol";

contract WOTSCommitTest is Test {
    function testCommitPkMatchesReference() public {
        bytes32[67] memory pk;
        for (uint256 i = 0; i < 67; i++) {
            pk[i] = bytes32(uint256(i));
        }
        bytes32 expected = 0x765d90c3c681035923f5df7760cedea68ebd2d977fc22a3752839104c6b33176;
        bytes32 commit = WOTS.commitPK(pk);
        assertEq(commit, expected);
    }
}
