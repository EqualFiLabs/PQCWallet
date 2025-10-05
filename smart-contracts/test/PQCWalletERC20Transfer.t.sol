// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {PQCWallet} from "../contracts/PQCWallet.sol";
import {IEntryPoint} from "../contracts/interfaces/IEntryPoint.sol";
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

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

contract PQCWalletERC20TransferTest is Test {
    using WOTS for bytes32;

    DummyEntryPoint internal entryPoint;
    PQCWallet internal wallet;
    MockERC20 internal token;

    address internal owner;
    address internal constant FIRST_ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        entryPoint = new DummyEntryPoint();
        token = new MockERC20("Mock Token", "MOCK");
        owner = makeAddr("owner");

        bytes32 seed = keccak256("seed");
        (, bytes32[67] memory pk) = WOTS.keygen(seed);
        bytes32 commit = WOTS.commitPK(pk);

        wallet = new PQCWallet(IEntryPoint(address(entryPoint)), owner, commit, keccak256("next"));
    }

    function test_walletTransfersMockERC20ToFirstAnvilAccount() public {
        uint256 mintedAmount = 1000 * 1e18;
        token.mint(address(wallet), mintedAmount);
        console2.log("Wallet balance after mint", token.balanceOf(address(wallet)));

        bytes memory transferCalldata = abi.encodeWithSelector(
            MockERC20.transfer.selector, FIRST_ANVIL_ACCOUNT, mintedAmount
        );

        vm.prank(address(entryPoint));
        wallet.execute(address(token), 0, transferCalldata);

        uint256 walletBalance = token.balanceOf(address(wallet));
        uint256 recipientBalance = token.balanceOf(FIRST_ANVIL_ACCOUNT);

        console2.log("Wallet balance after transfer", walletBalance);
        console2.log("First Anvil account balance", recipientBalance);

        assertEq(walletBalance, 0);
        assertEq(recipientBalance, mintedAmount);
    }
}
