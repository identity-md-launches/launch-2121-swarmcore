// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCore} from "../src/SwarmCore.sol";

/// @dev Edge and failure cases not covered by SwarmCore.t.sol: zero addresses on every entry point,
///      allowance boundaries, events that must not fire, and fuzzed senders and receivers.
contract SwarmCoreEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    SwarmCore internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new SwarmCore();
    }

    // ---------------------------------------------------------------------------------------------
    // Zero addresses
    // ---------------------------------------------------------------------------------------------

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(deployer);
        token.approve(alice, 10e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1e18);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, alice), 10e18, "a failed pull still spent allowance");
    }

    function test_transferFromZeroAddressRevertsOnAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(address(0), bob, 1);
    }

    function test_approveFromZeroAddressReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(alice, 1);
    }

    function test_transferFromZeroSenderReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(alice, 0);
    }

    function test_zeroAddressHoldsNothing() public view {
        assertEq(token.balanceOf(address(0)), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowance boundaries
    // ---------------------------------------------------------------------------------------------

    function test_transferFromExactAllowanceLeavesZero() public {
        vm.prank(deployer);
        token.approve(alice, 7e18);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 7e18);
        assertEq(token.allowance(deployer, alice), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceOneBelowMaxIsDecremented() public {
        uint256 allowed = type(uint256).max - 1;
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 5);
        assertEq(token.allowance(deployer, alice), allowed - 5);
    }

    function test_selfTransferFromStillNeedsAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_approveToZeroRevokes() public {
        vm.startPrank(deployer);
        token.approve(alice, 5e18);
        token.approve(alice, 0);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceIsPerSpenderAndPerOwner() public {
        vm.prank(deployer);
        token.approve(alice, 5e18);
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.allowance(alice, deployer), 0);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromEmitsTransferButNoApproval() public {
        vm.prank(deployer);
        token.approve(alice, 10e18);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 3e18);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(deployer))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(bob))));
        assertEq(abi.decode(logs[0].data, (uint256)), 3e18);
    }

    function test_failedTransferEmitsNothingAndChangesNothing() public {
        vm.recordLogs();
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (bob, 1)));
        assertFalse(ok);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzzed senders, receivers and amounts
    // ---------------------------------------------------------------------------------------------

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferBetweenAnyTwoAddresses(address from, address to, uint256 amount) public {
        if (from == address(0)) from = alice;
        if (to == address(0)) to = bob;
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(from, amount);

        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromAboveAllowanceRevertsAndKeepsState(uint256 allowed, uint256 attempt) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        attempt = bound(attempt, allowed + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, attempt)
        );
        token.transferFrom(deployer, bob, attempt);
        assertEq(token.allowance(deployer, alice), allowed);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveAnyValueIsStoredExactly(address spender, uint256 amount) public {
        if (spender == address(0)) spender = alice;
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, spender, amount);
        token.approve(spender, amount);
        assertEq(token.allowance(deployer, spender), amount);
    }

    /// @dev The launch splits: 10% to the distributor, a pool share, the rest to the requester.
    ///      However the supply is split, the parts add back up to it exactly.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_launchSplitIsExact(uint256 poolBps) public {
        poolBps = bound(poolBps, 0, 9_000);
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        address requester = makeAddr("requester");
        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        uint256 seed = (SUPPLY * poolBps) / 10_000;
        vm.startPrank(deployer);
        token.transfer(distributor, swarm);
        token.transfer(pool, seed);
        token.transfer(requester, token.balanceOf(deployer));
        vm.stopPrank();
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(pool), seed);
        assertEq(token.balanceOf(requester), SUPPLY - swarm - seed);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
