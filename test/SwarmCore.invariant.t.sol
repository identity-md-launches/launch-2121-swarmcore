// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCore} from "../src/SwarmCore.sol";

/// @dev Drives SwarmCore with bounded random calls from a fixed set of actors and keeps an
///      independent ledger (balances and allowances) of what each call must have done. Calls that
///      must fail are made too, and each one asserts it reverted and left the state untouched.
contract SwarmCoreHandler is Test {
    SwarmCore public immutable token;
    address[] public actors;

    // Ghost ledger: what each actor should hold and what each spender may still pull.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostMovedVolume;
    uint256 public calls;
    uint256 public successfulMoves;
    uint256 public expectedReverts;

    constructor(SwarmCore token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ---------------------------------------------------------------------------------------------
    // Successful paths
    // ---------------------------------------------------------------------------------------------

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        ++calls;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));

        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");

        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMovedVolume += amount;
        ++successfulMoves;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        ++calls;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = infinite ? type(uint256).max : bound(amount, 0, token.totalSupply() * 2);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        uint256 cap = allowed < token.balanceOf(from) ? allowed : token.balanceOf(from);
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount), "transferFrom returned false");

        if (ghostAllowance[from][spender] != type(uint256).max) ghostAllowance[from][spender] -= amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMovedVolume += amount;
        ++successfulMoves;
    }

    // ---------------------------------------------------------------------------------------------
    // Failure paths: each must revert with the right error and change nothing
    // ---------------------------------------------------------------------------------------------

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        ++calls;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transfer(to, amount);
        ++expectedReverts;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        ++calls;
        address from = _actor(fromSeed);
        amount = bound(amount, 0, token.balanceOf(from));

        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        ++expectedReverts;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        if (allowed == type(uint256).max) return; // an infinite allowance cannot be exceeded
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        token.transferFrom(from, to, amount);
        ++expectedReverts;
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 amount = held + bound(excess, 1, token.totalSupply());
        // Give the spender enough allowance that only the balance can be the reason for failure.
        vm.prank(from);
        token.approve(spender, amount);
        ghostAllowance[from][spender] = amount;

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        token.transferFrom(from, to, amount);
        ++expectedReverts;
    }
}

/// @dev Invariants over random call sequences. The token keeps everyone's balances, so the fixed
///      supply, the conservation of balances and the exactness of allowances must survive any order
///      of transfers, approvals and failed attempts.
contract SwarmCoreInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    SwarmCore internal token;
    SwarmCoreHandler internal handler;
    address internal deployer = makeAddr("deployer");
    address[] internal actors;

    function setUp() public {
        vm.prank(deployer);
        token = new SwarmCore();

        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("distributor"));

        handler = new SwarmCoreHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply(), "actor balances do not add up to the supply");
        assertEq(token.balanceOf(address(token)), 0, "tokens leaked into the token contract");
        assertEq(token.balanceOf(address(handler)), 0, "tokens leaked into the handler");
        assertEq(token.balanceOf(address(0)), 0, "tokens reached the zero address");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_balancesMatchGhostLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance drifted from ledger");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_allowancesMatchGhostLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance drifted from ledger"
                );
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_metadataAndDeployerAreFixed() public view {
        assertEq(token.name(), "SwarmCore");
        assertEq(token.symbol(), "SWARMCORE");
        assertEq(token.decimals(), 18);
        assertEq(token.DEPLOYER(), deployer);
        assertEq(address(token).balance, 0);
    }
}
