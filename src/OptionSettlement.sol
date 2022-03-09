// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "solmate/tokens/ERC1155.sol";

/**
   Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, american or
   european options. All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
   ERC-20 exercise asset using a chainlink VRF random number per unique option type for fair settlement. Options contracts
   are issued as fungible ERC-1155 tokens, with each token representing a contract. Option writers are additionally issued
   an ERC-1155 NFT representing a lot of contracts written for claiming collateral and exercise assignment. This design
   eliminates the need for market price oracles, and allows for permission-less writing, and gas efficient transfer, of
   a broad swath of traditional options.
*/

// TODO(Support both physically and cash settled options after the mvp?)
//enum Settlement {
//    Physical,
//    Cash
//}

enum Type {
    None,
    Option,
    Claim
}

struct Option {
    // Random seed created at the time of option chain creation
    uint256 settlementSeed;
    // The underlying asset to be received
    address underlyingAsset;
    //
    address exerciseAsset;
    uint256 exerciseTimestamp;
    uint256 expiryTimestamp;
}

struct Claim {
    // TODO(State about asset exercise, etc)
    uint256 option;
    // These are 1:1 contracts with the underlying struct
    uint256 amountWritten;
    uint256 amountExercised;
}

contract OptionSettlementEngine is ERC1155 {
    // TODO(Events for subgraph)
    // To increment the next available token id
    uint256 private _nextTokenId;

    // TODO(Null values here should return None from the enum, or design needs to change.)
    // Is this an option or a claim?
    mapping(uint256 => Type) public tokenType;

    // Accessor for Option contract details
    mapping(uint256 => Option) public option;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) public claim;

    // TODO(The URI should return relevant details about the contract or claim dep on ID)
    function uri(uint256) public pure virtual override returns (string memory) {
        // https://eips.ethereum.org/EIPS/eip-1155#metadata
        // Return base64 encoded json blob with metadata for rendering on the frontend
        return "";
    }

    // Here there must exist a way to get the data about a given token id transparently
}
