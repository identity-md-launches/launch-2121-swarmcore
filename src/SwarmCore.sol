// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SwarmCore (SWARMCORE)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 tokens (18 decimals) is minted
///         once, in the constructor, to the deployer. There is no owner, no minter, no pause, no
///         blacklist, no fee and no burn hook: after deployment the contract has no privileged
///         function at all, and the supply can never grow.
/// @dev The deployer is `msg.sender` of the constructor. At launch that is the ProjectFactory, which
///      then pays the supply out (swarm share to the MerkleDistributor, pool share to the Uniswap v4
///      pool, remainder to the requester). Nothing in this contract needs to know any of those
///      addresses, because every transfer, from anyone, moves exactly the amount requested.
contract SwarmCore is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "SwarmCore";

    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "SWARMCORE";

    /// @notice Total supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice The address the constructor minted the whole supply to.
    address public immutable DEPLOYER;

    /// @notice Emitted once, when the supply is minted in the constructor.
    /// @param to The deployer that received the whole supply.
    /// @param amount The whole supply, in minor units.
    event SupplyMinted(address indexed to, uint256 amount);

    /// @dev Mints `TOTAL_SUPPLY` to `msg.sender` and nothing else. Makes no external calls and
    ///      needs no address to have code, so it deploys identically on an empty chain.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        DEPLOYER = msg.sender;
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }
}
