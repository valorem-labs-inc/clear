# Trust Model
## Actors
There are 3 main actors in the core protocol:
- Protocol Admin
- Option Writer
- Option Holder

The **Protocol Admin** is the address to which protocol fees are swept. This address can update the Protocol Admin address, update the contract address of the TokenURIGenerator, enable/disable protocol fees, and sweep accrued fees. No other permissioned actions are possible.

**Option Writers** can create new option types and write options for any valid ERC-20 asset pair (excluding rebasing, fee-on-transfer, and ERC-777 tokens). Sufficient approval must be granted for the Clearinghouse to take custody of the requisite amount of the underlying asset. Once an option expires, the writer can redeem their Claim NFT for their share of the underlying and/or exercise assets.

**Option Holders** can transfer and exercise options that have been written. This is accomplished via a standard ERC-1155 transfer of the desired amount of option contracts from writer to holder. When exercising an option, they must have enough of the exercise asset, and similarly to when writing an option, they must have granted sufficient approval for the Clearinghouse on the ERC20 exercise asset.

## Assets
When an option is written, the Clearinghouse takes control of the underlying asset, transferring in the requisite amount. When an option is exercised, the Clearinghouse transfers in the requisite amount of the exerise asset and transfers out the underlying asset. When a claim is redeemed, the Clearinghouse transfers out that claimant's share of the exercise asset and any remaining, unexercised underlying asset.

## Actions
What can each actor do, when and with how much, of each asset?

- `ERC1155`
  - `anyone` can
    - check token balances of any address
    - check ownership of any token
    - check transfer approvals
    - check supported interfaces (ERC165 and ERC1155)
    - render the URI of any token
- `ValoremOptionsClearinghouse`
  - `anyone` can
    - get info for any Option fungible token ID
    - get info for any Claim non-fungible token ID
    - check position of the underlying and exercise assets of any token
    - check whether any token ID is a fungible Option or a non-fungible Claim
    - view the contract address of the TokenURIGenerator
    - check fee balance of any ERC20 asset
    - view protocol fee (expressed in basis points)
    - check if protocol fees are enabled
    - view Protocol Admin ("feeTo") address    
    - create an Option Type which does not exist yet
    - write a new Claim for a given Option Type
  - `ERC1155 Claim NFT holders` (i.e., Option Writers) can
    - write new options to a given Claim which they hold, before the expiry timestamp
    - redeem a Claim NFT which they hold for their share of the underlying and/or exercise assets, on or after the expiry timestamp
  - `ERC1155 Option fungible token holders` (i.e., Option Holders) can
    - transfer (up to their amount held) Option fungible tokens to another address
    - exercise (up to their amount held) Option fungible tokens, on or after the earliest exercise timestamp, and before the expiry timestamp
  - `Protocol Admin` can
    - enable/disable protocol fees
    - nominate a new Protocol Admin ("feeTo") address
    - accept a new Protocol Admin ("feeTo") address
    - update the contract address of the TokenURIGenerator
    - sweep accrued fees for any ERC20 asset to the Protocol Admin ("feeTo") address  
