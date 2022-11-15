# Valorem Options V1 Core

[Valorem](https://valorem.xyz/docs/valorem-options-litepaper/) is a DeFi money lego, enabling writing covered call and covered put, physically settled, American, European, or Exotic options.

This repository contains a binary smart contract system which encompasses the Valorem Options V1 Core. The Core contracts provide an option settlement engine upon which more complex systems can be built.

The Core is designed to be gas efficient, minimal, and provide a secure settlement system. The Core consists of a settlement engine which enables users to write options, exercise options, and redeem claims on assets in a given option lot, while handling fair assignment of exercises to claims written.

## Building the Project
1. Clone the git repository
2. Copy `.env.template` to `.env` and replace "XYZ" with your `RPC_URL` (e.g., https://mainnet.infura.io/v3/apikey or https://eth-mainnet.g.alchemy.com/v2/apikey)
3. Run `forge test` (this will install dependencies, build the project's smart contracts, and run the tests on a local fork of mainnet)

## Protocol Specification
- [Introduction](#introduction-to-the-protocol)
- [Trust Model](#trust-model)
- [Cucumber Features](./test/features)
- Protocol Invariants _(coming soon)_
- Glossary _(coming soon)_

### Introduction to the Protocol
The core of Valorem is the Settlement Engine, which follows the [ERC-1155 multi-token](https://eips.ethereum.org/EIPS/eip-1155) standard. Options can be written for any pair of valid ERC-20 assets (excluding rebasing, fee-on-transfer, and ERC-777 tokens). When written, an options contract is represented by semi-fungible Option tokens, which can be bought/sold/transferred between addresses like any ERC-1155 token.

The option writer's claim to the underlying asset(s) (if not exercised) and exercise asset(s) (if exercised) is represented by a non-fungible Option Lot Claim token. This Claim NFT can be redeemed for their share of the underlying plus exercise assets, based on current. The Settlement Engine uses a internal day bucketing approach, to facilitate fair assignment while minimizing O(n) complexity and gas costs.

The structure of an options contract is as follows:

- **Underlying asset:** the ERC-20 address of the asset to be received
- **Underlying amount:** the amount of the underlying asset contained within an option contract of this type
- **Exercise asset:** the ERC-20 address of the asset needed for exercise
- **Exercise amount:** the amount of the exercise asset required to exercise this option
- **Earliest exercise timestamp:** the timestamp after which this option may be exercised
- **Expiry timestamp:** the timestamp before which this option must be exercised

The Valorem core protocol is unopinionated on the type of option (call vs. put), where, when, or for how much an option is bought/sold, and whether or not the option is profitable when exercised. Because all contracts are fully collateralized, options written on the Settlement Engine are TODO.

Read the [Valorem litepaper](https://valorem.xyz/docs/valorem-options-litepaper/) for more insight into the business use cases that Valorem enables.

### Trust Model
#### Actors
There are 3 main actors in the core protocol:
- Protocol Admin
- Option Writer
- Option Holder

The **Protocol Admin** is the address to which protocol fees are swept, and can update the Protocol Admin address. No other permissioned actions are possible.

**Option Writers** can create new option types and write option lots for any valid ERC-20 asset pair (excluding rebasing, fee-on-transfer, and ERC-777 tokens). Sufficient approval must be granted for the Settlement Engine to take custody of the requisite amount of the underlying asset. Once an option lot expires, the writer can redeem their Claim NFT to their share of the underlying and/or exercise assets.

**Option Holders** can acquire options once written. This is accomplished via a simple ERC-1155 transaction to transfer the desired amount of option contracts. When exercising an option, they must hold enough of the exercise asset, and similarly to when writing an option, they must have granted sufficient approval for the Settlement Engine on the ERC20 exercise asset.

#### Assets
Each asset pair for which an option is written is custodied by the Settlement Engine. When an option is written, TODO. When an option is exercised, TODO. When an option lot claim is redeemed, TODO. The core Settlement Engine is agnostic with regard to the buying or selling of options contracts. These are ERC-1155 semi-fungible tokens which can be transacted freely, from the writer to any party wishing to hold and potentially exercise the option before expiry. The Settlement Engine emits a standard ERC-1155 TransferSingle event when 1 or more options of a given type changes hands.

#### Actions
What can each actor do, when, with how much of each asset?

- `ERC1155`
  - `anyone` can
    - check balances of any address
    - check ownership of any token
    - check transfer approvals
    - check supported interfaces (ERC165 and ERC1155)
    - render the URI of any token
- `OptionSettlementEngine`
  - `anyone` can
    - check protocol fee (expressed in basis points)
    - check protocol balance of any ERC20 asset
    - check Protocol Admin ("feeTo") address
    - check whether any token ID is an Option or an Option Lot Claim
    - check positions of the underlying and exercise assets of any token
    - get Option info for any token ID
    - get Option Lot Claim info for any token ID
    - check amount of a given TODO
    - sweep accrued fees for any ERC20 asset to the Protocol Admin ("feeTo") address
    - create an Option Type which does not exist yet
    - write a new option lot for a given Option Type
  - `ERC1155 Option fungible token holders` (i.e., Option Writers) can
    - transfer (up to their amount held) Option fungible tokens to another address
    - write new options to a given Option Lot Claim which they hold, before the expiry timestamp
    - redeem a Claim NFT which they hold for their share of the underlying and/or exercise assets, on or after the expiry timestamp
  - `ERC1155 Option Lot Claim NFT holders` (i.e., Option Holders) can
    - exercise (up to their amount held) Option fungible tokens, on or after the earliest exercise timestamp, and before the expiry timestamp
  - `Protocol Admin` can
    - update the Protocol Admin ("feeTo") address

## Core Interface

The core exposes an interface for users of the protocol, which is documented in the codebase. Additional documentation is provided here.

### IOptionSettlementEngine

`IOptionSettlementEngine` is an
[ERC-1155 multi-token](https://eips.ethereum.org/EIPS/eip-1155)
interface extended to provide an interface to the Valorem protocol options
settlement system.

#### Enums

##### Type

The `Type` enum contains information about the type of a given token in the
settlement engine.

```solidity
enum Type {
        None,
        Option,
        Claim
    }
```

#### Errors

##### TokenNotFound

The `TokenNotFound()` error occurs when a token is not found in the engine.

```solidity
error TokenNotFound();
```

#### Events

##### FeeSwept

The `FeeSwept` event is emitted when accrued protocol fees for a given token are
swept to the `feeTo` address.

```solidity
event FeeSwept(
        address indexed token,
        address indexed feeTo,
        uint256 amount
    );
```

##### NewOptionType

The `NewOptionType` event is emitted when a new unique options chain is created.

```solidity
event NewOptionType(
        uint256 indexed optionId,
        address indexed exerciseAsset,
        address indexed underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    );
```

##### OptionsExercised

The `OptionsExercised` event is emitted on successful `exercise` of options.

```solidity
event OptionsExercised(
        uint256 indexed optionId,
        address indexed exercisee,
        uint112 amount
    );
```

##### OptionsWritten

The `OptionsWritten` event is emitted when `write` is called to write new options.

```solidity
event OptionsWritten(
        uint256 indexed optionId,
        address indexed writer,
        uint256 claimId,
        uint112 amount
    );
```

##### FeeAccrued

The `FeeAccrued` event is emitted on `write` or `exercise`.

```solidity
event FeeAccrued(
        address indexed asset,
        address indexed payor,
        uint256 amount
    );
```

##### ClaimRedeemed

The `ClaimRedeem` event is emitted when `redeem` is called on a `Claim`.

```solidity
event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        address exerciseAsset,
        address underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount
    );
```

##### ExerciseAssigned

The `ExerciseAssigned` event is emitted when an exercise of an option is assigned to a claim.

```solidity
event ExerciseAssigned(
        uint256 indexed claimId, 
        uint256 indexed optionId, 
        uint112 amountAssigned
    );
```

#### Functions

##### feeBalance

The `feeBalance` function returns the balance of protocol fees for a given `token`
which have not been swept yet.

```solidity
function feeBalance(address token) external view returns (uint256);
```

##### feeBps

Returns the protocol fee in basis points charged to writers in the underlying
asset and exercisers in the exercise asset.

```solidity
function feeBps() external view returns (uint8);
```

##### feeTo

The `feeTo` function returns the address to which protocol fees are swept.

```solidity
function feeTo() external view returns (address);
```

##### tokenType

Returns the token `Type` enum for a given `tokenId`.

```solidity
function tokenType(uint256 tokenId) external view returns (Type);
```


##### option

Returns `Option` struct details about a given `tokenId` if that token is a vToken.

```solidity
function option(uint256 tokenId)
        external
        view
        returns (Option memory optionInfo);
```

##### claim

Returns `Claim` struct details about a given `tokenId` if that token is a claim NFT.

```solidity
function claim(uint256 tokenId)
        external
        view
        returns (Claim memory claimInfo);
```

##### setFeeTo

Callable only by the present `feeTo` address, changes the `feeTo` address.

```solidity
function setFeeTo(address newFeeTo) external;
```

##### hashToOptionToken

Returns the `optionId` for the hash `keccak256(abi.encode(Option memory))` where `settlementSeed` is set to
`0` at the time of hashing if it exists.

```solidity
function hashToOptionToken(bytes32 hash)
        external
        view
        returns (uint256 optionId);
```

##### sweepFees

Sweeps the fees if the balance for a token is greater than 1 wei, for each token in
`tokens`.

```solidity
function sweepFees(address[] memory tokens) external;
```

##### NewOptionType

Creates a new options chain if one doesn't already exist for the hash `keccak256(abi.encode(Option memory))` where `settlementSeed` is set to
`0`.

```solidity
 function newOptionType(Option memory optionInfo)
        external
        returns (uint256 optionId);
```

##### write

Writes `amount` of `optionId` `Option` and sends the caller vTokens and a claim NFT.

```solidity
function write(uint256 optionId, uint112 amount)
        external
        returns (uint256 claimId);
```

##### exercise

Exercises `amount` of `optionId`, transferring in the exercise asset, and
transferring out the underlying asset if all requirements are met.

```solidity
function exercise(uint256 optionId, uint112 amount) external;
```

##### redeem

Redeems `claimId` for the underlying asset(s) if `msg.sender` is the caller and
the options chain for the claim has reached expiry. Burns the claim NFT on success.

```solidity
function redeem(uint256 claimId) external;
```

##### underlying

Returns the `Underlying` struct about assets for 1 wei of a given `tokenId` if
that token exists.

```solidity
function underlying(uint256 tokenId)
        external
        view
        returns (Underlying memory underlyingPositions);
```

#### Structs

##### Claim

The `Claim` struct contains information about a claim, generated when a writer calls
`write`. Every claim is linked to an `option` token.

```solidity
struct Claim {
        uint256 option;
        uint112 amountWritten;
        uint112 amountExercised;
        bool claimed;
    }
```

##### Option

The `Option` struct contains all data about an option chain/token and is keyed on the
unique hash `keccak256(abi.encode(Option memory))` where `settlementSeed` is set to
`0` at the time of hashing.

```solidity
    struct Option {
        address underlyingAsset;
        uint40 exerciseTimestamp;
        uint40 expiryTimestamp;
        address exerciseAsset;
        uint96 underlyingAmount;
        uint160 settlementSeed;
        uint96 exerciseAmount;
    }
```

##### Underlying

The `Underlying` struct contains information about the underlying assets for 1
wei of a given token ID in the settlement engine.

```solidity
struct Underlying {
        address underlyingAsset;
        int256 underlyingPosition;
        address exerciseAsset;
        int256 exercisePosition;
    }
```

## Security Information
- Audit info XYZ
- Bug bounty info XYZ
- Security contact info XYZ
