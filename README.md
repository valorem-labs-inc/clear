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
- [Solidity Docs](TODO)
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

**Option Holders** can acquire options that have been written. This is accomplished via a standard ERC-1155 transaction to transfer the desired amount of option contracts. When exercising an option, they must hold enough of the exercise asset, and similarly to when writing an option, they must have granted sufficient approval for the Settlement Engine on the ERC20 exercise asset.

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
    - view protocol fee (expressed in basis points)
    - view Protocol Admin ("feeTo") address
    - check fee balance of any ERC20 asset
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

## Security Information
- Audit info TODO
- Bug bounty info TODO
- Security contact info TODO
