# SwarmCore (SWARMCORE)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Setting | Value |
| --- | --- |
| Solidity contract | `SwarmCore` (`src/SwarmCore.sol`) |
| `name()` | `SwarmCore` |
| `symbol()` | `SWARMCORE` |
| `decimals()` | 18 |
| Total supply | 1,000,000,000 SWARMCORE = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Owner / admin | none |

## Behaviour

- The constructor mints the whole supply to the deployer and emits `Transfer(0, deployer, supply)`
  and `SupplyMinted(deployer, supply)`. The deployer is also recorded in the immutable `DEPLOYER`.
- Every transfer, from any address, moves exactly the amount requested. There is no fee, tax,
  reflection, burn-on-transfer, cooldown, max-wallet or max-transaction rule.
- There is no `mint`, `burn`, `pause`, `blacklist`, `freeze`, `seize`, `owner`, upgrade or
  initializer. The supply can never grow after deployment, and nobody can move or lock a holder's
  balance except the holder (or a spender the holder approved).
- The contract makes no external calls and does not require any address to have code, so it deploys
  identically on an empty chain. The runtime contains no `DELEGATECALL`, `CALLCODE` or
  `SELFDESTRUCT`.
- The contract rejects plain ether (no `receive` or `fallback`).

## Implementation

`SwarmCore` inherits OpenZeppelin Contracts v5.4.0 `ERC20` unchanged. The required files are
vendored as ordinary sources under `lib/openzeppelin-contracts/` (MIT, see its `LICENSE`).
`lib/forge-std/` is forge-std v1.14.0, vendored the same way. No git submodules are used.

Named constants:

| Constant | Value | Why |
| --- | --- | --- |
| `TOKEN_NAME` | `"SwarmCore"` | the requested name |
| `TOKEN_SYMBOL` | `"SWARMCORE"` | the requested symbol |
| `TOTAL_SUPPLY` | `1_000_000_000 * 1e18` | the requested supply with 18 decimals |

## Assumptions

- The brief asks for a plain token: name, symbol and supply only. No transfer rules, taxes, vesting,
  governance or admin powers were requested, so none are implemented.
- "Minted to the deployer" means `msg.sender` of the constructor. At launch that is the IdentityMD
  ProjectFactory, which pays the supply out. The token has no notion of the factory, pool manager
  or distributor, because no address is exempted from anything: with exact transfers nothing needs
  exempting.
- 18 decimals is the ERC-20 default and the value the brief states.

## Deployment parameters (for the launch manifest)

These are the launch's values as given to this job; the manifest step writes `launch.json`, not this
repository.

| Field | Value |
| --- | --- |
| `token.contract` | `SwarmCore` |
| `token.name` | `SwarmCore` |
| `token.symbol` | `SWARMCORE` |
| `token.decimals` | `18` |
| `token.constructorArgs` | `[]` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `contracts` | `[]` (no application contracts) |
| `pool.pairedCurrency` | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (IMD on Ethereum) |
| `pool.fee` | `12500` |
| `pool.tickSpacing` | `60` |
| `pool.initialPrice` | `79228162514264337593543950336` |
| `economics` | `{"poolBps":8000,"initialMarketCapWei":"2500000000000000000000","remainderTo":"0x0f44a55663e888bb63618a0c31b68cbc6c01aa71"}` |

Supply distribution performed by the factory after the constructor mints everything to it:

| Share | Recipient |
| --- | --- |
| 10% (100,000,000) | the launch's MerkleDistributor (swarm share) |
| 80% (800,000,000) | single-sided Uniswap v4 pool against IMD, opened at a 2,500 IMD market cap |
| 10% (100,000,000) | `0x0f44a55663e888bb63618a0c31b68cbc6c01aa71` (economics.remainderTo) |

## After launch

Nothing to configure. The token has no owner and no settable values. There are no outside
services, oracles or addresses it depends on.

## Operational responsibilities

- IdentityMD's deployer launches the token through the ProjectFactory. This repository does not
  deploy, broadcast, verify on an explorer or hold keys. Explorer source verification after the
  launch is an open item for the deployer (`forge verify-contract` with the pinned settings below).
- There is no admin, so there is no key to rotate, no multisig to hand over to, and no emergency
  switch. Anything that goes wrong after launch cannot be fixed in the token itself; this is by
  design for a fixed-supply, trust-minimised token.
- Holders are responsible for their own approvals. `approve` overwrites the previous allowance (the
  standard ERC-20 race); an unlimited allowance is never decremented.
- Tests passing is not a security audit. The contract is a thin wrapper over an audited library,
  but an independent adversarial review before release remains good practice.

## Build and test

`foundry.toml` pins `solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on with 200 runs, and
`bytecode_hash = "none"` with `cbor_metadata = false` so the deployed bytes are reproducible.
`ffi` is off and no filesystem permissions are granted.

```sh
forge build
forge test
forge fmt --check
```

The fuzz tests are deterministic under any seed; they were run with the verifier's
`FOUNDRY_FUZZ_SEED` as well as the default.

Tests (`test/SwarmCore.t.sol`) cover metadata, the exact supply minted to the deployer (EOA, fuzzed
address and contract deployer), transfer and allowance success paths, transfer and allowance failure
paths with the exact OpenZeppelin custom errors, conservation of supply across chained transfers,
the absence of any mint/pause/freeze/seize/owner function from both a stranger and the deployer,
rejection of plain ether, and a runtime scan for `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT`.

Tools run: `forge build`, `forge test` (unit and fuzz), `forge fmt --check`. Slither and Mythril
were not available on this machine and did not run.
