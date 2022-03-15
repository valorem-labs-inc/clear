// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "base64/Base64.sol";
import "solmate/tokens/ERC1155.sol";

/**
   Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, options.
   All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
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
    // The underlying asset to be received
    address underlyingAsset;
    // The timestamp after which this option may be exercised
    uint64 exerciseTimestamp;
    // The address of the asset needed for exercise
    address exerciseAsset;
    // The timestamp before which this option must be exercised
    uint64 expiryTimestamp;
    // Random seed created at the time of option chain creation
    uint256 settlementSeed;
    // The amount of the underlying asset contained within an option contract of this type
    uint256 underlyingAmount;
    // The amount of the exercise asset required to exercise this option
    uint256 exerciseAmount;
}

struct Claim {
    // Which option was written
    uint256 option;
    // These are 1:1 contracts with the underlying Option struct
    // The number of contracts written in this claim
    uint256 amountWritten;
    // The amount of contracts assigned for exercise to this claim
    uint256 amountExercised;
    // The two amounts above along with the option info, can be used to calculate the underlying assets
    bool claimed;
}

contract OptionSettlementEngine is ERC1155 {
    // TODO(Interface file to interact without looking at the internals)

    // TODO(Events for subgraph)

    // To increment the next available token id
    uint256 private _nextTokenId;

    // TODO(Null values here should return None from the enum, or design needs to change.)
    // Is this an option or a claim?
    mapping(uint256 => Type) public tokenType;

    // Accessor for Option contract details
    mapping(uint256 => Option) public option;

    // This is used to check if an Option chain already exists
    mapping(bytes32 => bool) private chainMap;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) public claim;

    // TODO(The URI should return relevant details about the contract or claim dep on ID)
    function uri(uint256) public pure virtual override returns (string memory) {
        // https://eips.ethereum.org/EIPS/eip-1155#metadata
        // Return base64 encoded json blob with metadata for rendering on the frontend
        //{
        //    "title": "Token Metadata",
        //"type": "object",
        //"properties": {
        //"name": {
        //"type": "string",
        //"description": "Identifies the asset to which this token represents"
        //},
        //"decimals": {
        //"type": "integer",
        //"description": "The number of decimal places that the token amount should display - e.g. 18, means to divide the token amount by 1000000000000000000 to get its user representation."
        //},
        //"description": {
        //"type": "string",
        //"description": "Describes the asset to which this token represents"
        //},
        //"image": {
        //"type": "string",
        //"description": "A URI pointing to a resource with mime type image/* representing the asset to which this token represents. Consider making any images at a width between 320 and 1080 pixels and aspect ratio between 1.91:1 and 4:5 inclusive."
        //},
        //"properties": {
        //"type": "object",
        //"description": "Arbitrary properties. Values may be strings, numbers, object or arrays."
        //}
        //}
        //    }
        string memory json = Base64.encode(
            bytes(string(abi.encodePacked("{}")))
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // TODO(random number should be generated from vrf)
    function newOptionsChain(Option memory optionInfo)
        public
        returns (uint256 tokenId)
    {
        // Check that a duplicate chain doesn't exist, and if it does, revert
        bytes32 chainKey = keccak256(abi.encode(optionInfo));
        require(chainMap[chainKey] == false, "This option chain exists");

        // Else, create new options chain

        // Zero out random number for gas savings and to await randomness
        optionInfo.settlementSeed = 0;

        // Create option token and increment
        tokenType[_nextTokenId] = Type.Option;
        require(
            optionInfo.expiryTimestamp >= (block.timestamp + 86400),
            "Expiry < 24 hours from now."
        );
        require(
            optionInfo.expiryTimestamp >=
                (optionInfo.exerciseTimestamp + 86400),
            "Exercise < 24 hours from exp"
        );
        require(
            optionInfo.exerciseAsset != optionInfo.underlyingAsset,
            "Underlying == Exercise"
        );
        // TODO(Do we need to check that the ERC20's in question exist here?)
        option[_nextTokenId] = optionInfo;

        // TODO(This should emit an event about the creation for indexing in a graph)

        tokenId = _nextTokenId;

        // Increment the next token id to be used
        _nextTokenId += 1;
        chainMap[chainKey] = true;
    }

    // TODO(Write option)

    // TODO(Exercise option)

    // TODO(Use claim)

    // TODO(Get info about options contract)

    // TODO(Get info about a claim)
}
