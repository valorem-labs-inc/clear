# Trust Model
## Actors
There are 3 main actors in the core protocol:
- Protocol Admin
- Option Writer
- Option Holder

The **Protocol Admin** is the address to which protocol fees are swept, and can update the Protocol Admin address. No other permissioned actions are possible.

**Option Writers** can create new option types and write option lots for any valid ERC-20 asset pair (excluding rebasing, fee-on-transfer, and ERC-777 tokens). Sufficient approval must be granted for the Settlement Engine to take custody of the requisite amount of the underlying asset. Once an option lot expires, the writer can redeem their Claim NFT to their share of the underlying and/or exercise assets.

**Option Holders** can buy options that have been written. This is accomplished via a standard ERC-1155 transfer of the desired amount of option contracts from writer to holder. When exercising an option, they must have enough of the exercise asset, and similarly to when writing an option, they must have granted sufficient approval for the Settlement Engine on the ERC20 exercise asset.

## Assets
When an option is written, the Settlement Engine takes custody of the underlying asset, transferring in the requisite amount. When an option is exercised, the Engine transfers in the requisite amount of the exerise asset and transfers out the underlying asset. When an option lot claim is redeemed, the Engine transfers out that claimant's share of the exercise asset and possible unexercised underlying asset.

## Actions
What can each actor do, when, with how much, of each asset?

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
    - check info about a given Option Lot Claim Bucket
    - sweep accrued fees for any ERC20 asset to the Protocol Admin ("feeTo") address
    - create an Option Type which does not exist yet
    - write a new option lot for a given Option Type
  - `ERC1155 Option Lot Claim NFT holders` (i.e., Option Writers) can
    - write new options to a given Option Lot Claim which they hold, before the expiry timestamp
    - redeem a Claim NFT which they hold for their share of the underlying and/or exercise assets, on or after the expiry timestamp
  - `ERC1155 Option fungible token holders` (i.e., Option Holders) can
    - transfer (up to their amount held) Option fungible tokens to another address
    - exercise (up to their amount held) Option fungible tokens, on or after the earliest exercise timestamp, and before the expiry timestamp
  - `Protocol Admin` can
    - update the Protocol Admin ("feeTo") address