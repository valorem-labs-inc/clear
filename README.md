# Valorem Options V1 Core

![ci](https://github.com/valorem-labs-inc/valorem-core/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/valorem-labs-inc/valorem-core/branch/master/graph/badge.svg?token=M52NC4Q3SW)](https://codecov.io/gh/valorem-labs-inc/valorem-core)

This repository contains a binary smart contract system comprised of many libraries,
which together make the Valorem Options V1 Core. The Core contracts provide an option
settlement engine upon which more complex systems can be built.

The Core is designed to be gas efficient, minimal, and provide a secure settlement
system. The Core consists, primarily, of a settlement engine which allows users
to write options, exercise options, redeem claims for assets, and settles assignments
of exercises to claims written.

## Building the Project
1. Clone the git repository
2. Copy `.env.template` to `.env` and replace "XYZ" with your `RPC_URL` (e.g., https://mainnet.infura.io/v3/apikey or https://eth-mainnet.g.alchemy.com/v2/apikey)
3. Run `forge test` (this will install dependencies, build the project's smart contracts, and run the unit tests on a local fork of mainnet)

## Core Interface

The core exposes an interface for users of the protocol, which is documented in the
codebase, additional documentation is provided here.

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
        uint40 earliestExerciseTimestamp,
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
        uint40 earliestExerciseTimestamp;
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
