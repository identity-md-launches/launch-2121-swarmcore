// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCore} from "../src/SwarmCore.sol";

contract SwarmCoreTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    SwarmCore internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed to, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        token = new SwarmCore();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "SwarmCore");
        assertEq(token.symbol(), "SWARMCORE");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "SwarmCore");
        assertEq(token.TOKEN_SYMBOL(), "SWARMCORE");
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_wholeSupplyMintedToDeployerInConstructor() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.DEPLOYER(), deployer);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsMintTransferAndSupplyMinted() public {
        address other = makeAddr("otherDeployer");
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), other, SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(other, SUPPLY);
        vm.prank(other);
        new SwarmCore();
    }

    /// @dev Whoever deploys receives the supply: at launch that is the factory, here any address.
    function testFuzz_deployerReceivesWholeSupply(address anyDeployer) public {
        vm.assume(anyDeployer != address(0));
        vm.prank(anyDeployer);
        SwarmCore fresh = new SwarmCore();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(anyDeployer), SUPPLY);
        assertEq(fresh.DEPLOYER(), anyDeployer);
    }

    /// @dev A contract deployer (the factory at launch) receives the supply exactly like an EOA.
    function test_contractDeployerReceivesWholeSupply() public {
        DeployerProbe probe = new DeployerProbe();
        SwarmCore fresh = probe.deployToken();
        assertEq(fresh.balanceOf(address(probe)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Transfers: success
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        uint256 amount = 1_234_567 * 1e18;
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, amount);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 1e18));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// @dev The launch flows (factory -> distributor -> claimant, factory -> pool, pool -> trader)
    ///      must each move exactly what they say. A chain of hops loses nothing.
    function testFuzz_transferChainConservesSupplyAndLosesNothing(uint256 amount, uint256 claim) public {
        amount = bound(amount, 0, SUPPLY);
        claim = bound(claim, 0, amount);
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(bob, claim);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount - claim);
        assertEq(token.balanceOf(bob), claim);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Transfers: failure
    // ---------------------------------------------------------------------------------------------

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferRevertsWhenExceedingBalanceByOne() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, type(uint256).max);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempt));
        token.transfer(bob, attempt);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowances: success
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 5e18);
        assertTrue(token.approve(alice, 5e18));
        assertEq(token.allowance(deployer, alice), 5e18);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 5e18);
        token.approve(alice, 2e18);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 2e18);
    }

    function test_transferFromSpendsAllowanceExactly() public {
        vm.prank(deployer);
        token.approve(alice, 10e18);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 4e18);
        assertTrue(token.transferFrom(deployer, bob, 4e18));
        assertEq(token.balanceOf(bob), 4e18);
        assertEq(token.balanceOf(deployer), SUPPLY - 4e18);
        assertEq(token.allowance(deployer, alice), 6e18);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 4e18);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 4e18);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, allowed);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, spent));
        assertEq(token.balanceOf(bob), spent);
        assertEq(token.allowance(deployer, alice), allowed - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Allowances: failure
    // ---------------------------------------------------------------------------------------------

    function test_transferFromWithoutAllowanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromAboveAllowanceReverts() public {
        vm.prank(deployer);
        token.approve(alice, 3e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 3e18, 3e18 + 1));
        token.transferFrom(deployer, bob, 3e18 + 1);
    }

    function test_transferFromAboveBalanceRevertsEvenWithAllowance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, stranger, 1);
    }

    function test_approveZeroSpenderReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged hand: nothing mints, pauses, freezes or seizes
    // ---------------------------------------------------------------------------------------------

    function test_noAdminCallIncreasesSupplyOrCreditsCaller() public {
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "owner()",
            "renounceOwnership()"
        ];
        address[2] memory callers = [stranger, deployer];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < signatures.length; ++i) {
                bytes memory data = abi.encodeWithSignature(signatures[i], callers[c], type(uint128).max);
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
                assertEq(token.totalSupply(), SUPPLY, signatures[i]);
                assertEq(token.balanceOf(stranger), 0, signatures[i]);
            }
        }
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        uint256 held = SUPPLY / 1_000;
        vm.prank(deployer);
        token.transfer(alice, held);
        string[13] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "burn(uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        // The deployer holds no allowance from alice, so it cannot pull from her either.
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), held);
        vm.prank(alice);
        assertTrue(token.transfer(bob, held / 2));
        assertEq(token.balanceOf(bob), held / 2);
        assertEq(token.balanceOf(alice), held - held / 2);
    }

    function test_plainEtherTransferReverts() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Bytecode: nothing delegates, nothing self-destructs, fits EIP-170
    // ---------------------------------------------------------------------------------------------

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    function test_creationCodeTakesNoConstructorArguments() public {
        // Deploying the raw creation code with nothing appended succeeds and mints to the creator.
        bytes memory code = type(SwarmCore).creationCode;
        address created;
        vm.prank(deployer);
        assembly ("memory-safe") {
            created := create(0, add(code, 32), mload(code))
        }
        assertTrue(created != address(0));
        assertEq(IERC20(created).balanceOf(deployer), SUPPLY);
        assertEq(IERC20(created).totalSupply(), SUPPLY);
    }
}

/// @dev Stands in for the factory: a contract whose constructor-less call deploys the token.
contract DeployerProbe {
    function deployToken() external returns (SwarmCore) {
        return new SwarmCore();
    }
}
