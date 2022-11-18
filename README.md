# Valorem Options V1 Core

![ci](https://github.com/valorem-labs-inc/valorem-core/actions/workflows/CI.yml/badge.svg)
[![codecov](https://codecov.io/gh/valorem-labs-inc/valorem-core/branch/master/graph/badge.svg?token=M52NC4Q3SW)](https://codecov.io/gh/valorem-labs-inc/valorem-core)

[Valorem](https://valorem.xyz/) is a DeFi money lego, enabling writing covered call and covered put, physically settled, American, European, or Exotic options.

- [Introduction](#introduction-to-the-protocol)
- [Trust Model](./test/trust-model.md)
- [Cucumber Features](./test/features/)
- [Building the Project](#building-the-project)
- [Security Contact Info](#security-contact-info)

## Introduction to the Protocol

The Valorem Options V1 Core consists of a settlement engine which allows users to write options, exercise options, and redeem claims on assets, while handling fair assignment of exercises to claims written. It is designed to be gas efficient, minimal, and provide a secure settlement layer upon which more complex systems can be built.

The Settlement Engine follows the [ERC-1155 multi-token](https://eips.ethereum.org/EIPS/eip-1155) standard. Options can be written for any pair of valid ERC-20 assets (excluding rebasing, fee-on-transfer, and ERC-777 tokens). When written, an options contract is represented by semi-fungible Option tokens, which can be bought/sold/transferred between addresses like any ERC-1155 token.

An option writer's claim to the underlying asset(s) (if not exercised) and exercise asset(s) (if exercised) is represented by a non-fungible option lot Claim token. This Claim NFT can be redeemed for their share of the underlying plus exercise assets, based on currently exercised.

The structure of an option is as follows:

- **Underlying asset:** the ERC-20 address of the asset to be received upon exercise.
- **Underlying amount:** the amount of the underlying asset contained within an option of this type.
- **Exercise asset:** the ERC-20 address of the asset needed for exercise.
- **Exercise amount:** the amount of the exercise asset required to exercise this option.
- **Exercise timestamp:** the timestamp after which this option can be exercised and physically settled.
- **Expiry timestamp:** the timestamp before which this option can be exercised.

The Core is unopinionated on the type of option (call vs. put), where, when, or for how much an option is bought/sold, and whether or not the option is profitable when exercised. Because all options written with Valorem are fully collateralized, physical settlement at exercise or redeem time is instant and gas-efficient.

Read the [litepaper](https://valorem.xyz/docs/valorem-options-litepaper/) for more insight into the business use cases that Valorem enables.

## Building the Project
1. Clone the git repository
2. Copy `.env.template` to `.env` and replace "XYZ" with your `RPC_URL` (e.g., https://mainnet.infura.io/v3/apikey or https://eth-mainnet.g.alchemy.com/v2/apikey)
3. Run `forge test` (this will install dependencies, build the project's smart contracts, and run the tests on a local fork of mainnet)

## Security Contact Info
- Audit info _(coming soon)_
- Bug bounty info _(coming soon)_
- Security contact info _(coming soon)_
