// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "base64/Base64.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC1155.sol";
import "solmate/utils/SafeTransferLib.sol";

/**
   Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, options.
   All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
   ERC-20 exercise asset using a chainlink VRF random number per unique option type for fair settlement. Options contracts
   are issued as fungible ERC-1155 tokens, with each token representing a contract. Option writers are additionally issued
   an ERC-1155 NFT representing a lot of contracts written for claiming collateral and exercise assignment. This design
   eliminates the need for market price oracles, and allows for permission-less writing, and gas efficient transfer, of
   a broad swath of traditional options.
*/

enum Type {
    None,
    Option,
    Claim
}

// TODO(Consider converting require strings to errors)
// TODO(An enum here indicating if the option is a put or a call would be redundant, but maybe useful?)

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

// TODO(Add VRF)
contract OptionSettlementEngine is ERC1155 {
    // TODO(Interface file to interact without looking at the internals)

    // TODO(Events for subgraph)

    // TODO(Do we need to track internal balances)

    uint8 public immutable feeBps = 5;

    // TODO(Implement setters for this and a real address)
    address public feeTo = 0x36273803306a3C22bc848f8Db761e974697ece0d;

    // To increment the next available token id
    uint256 private _nextTokenId;

    // TODO(Null values here should return None from the enum, or design needs to change.)
    // Is this an option or a claim?
    mapping(uint256 => Type) public tokenType;

    // Accessor for Option contract details
    mapping(uint256 => Option) public option;

    // TODO(Should this be a public uint256 lookup of the token id if exists?)
    // This is used to check if an Option chain already exists
    mapping(bytes32 => bool) private chainMap;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) public claim;

    // TODO(The URI should return relevant details about the contract or claim dep on ID)
    function uri(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(tokenType[tokenId] != Type.None, "Token does not exist");
        // TODO(Implement metadata/uri builder)
        string memory json = Base64.encode(
            bytes(string(abi.encodePacked("{}")))
        );
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function newOptionsChain(Option memory optionInfo)
        external
        returns (uint256 tokenId)
    {
        // TODO(Transfer the link fee here)
        // Check that a duplicate chain doesn't exist, and if it does, revert
        bytes32 chainKey = keccak256(abi.encode(optionInfo));
        require(chainMap[chainKey] == false, "This option chain exists");

        // Else, create new options chain

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

        // Zero out random number for gas savings and to await randomness
        optionInfo.settlementSeed = 0;

        // TODO(random number should be generated from vrf and stored to settlementSeed here)
        optionInfo.settlementSeed = 42;

        // Create option token and increment
        tokenType[_nextTokenId] = Type.Option;

        // Check that both tokens are ERC20 by instantiating them and checking supply
        ERC20 underlying = ERC20(optionInfo.underlyingAsset);
        ERC20 exercise = ERC20(optionInfo.exerciseAsset);

        // Check total supplies and ensure the option will be exercisable
        require(
            underlying.totalSupply() >= optionInfo.underlyingAmount,
            "Invalid Supply"
        );
        require(
            exercise.totalSupply() >= optionInfo.exerciseAmount,
            "Invalid Supply"
        );

        option[_nextTokenId] = optionInfo;

        // TODO(This should emit an event about the creation for indexing in a graph)

        tokenId = _nextTokenId;

        // Increment the next token id to be used
        ++_nextTokenId;
        chainMap[chainKey] = true;
    }

    function writeOptions(uint256 tokenId, uint256 amount) external {
        require(tokenType[tokenId] == Type.Option, "Token is not an option");
        require(
            option[tokenId].settlementSeed != 0,
            "Settlement seed not populated"
        );

        Option storage optionRecord = option[tokenId];

        uint256 tx_amount = amount * optionRecord.underlyingAmount;

        // Transfer the requisite underlying asset
        SafeTransferLib.safeTransferFrom(
            ERC20(optionRecord.underlyingAsset),
            msg.sender,
            address(this),
            tx_amount
        );

        // TODO(Consider an internal balance counter here and aggregating these in a fee sweep)
        // TODO(Ensure rounding down or precise math here)
        // Transfer fee to writer
        SafeTransferLib.safeTransfer(
            ERC20(optionRecord.underlyingAsset),
            feeTo,
            ((tx_amount / 10000) * feeBps)
        );
        // TODO(Do we need any other internal balance counters?)

        uint256 claimTokenId = _nextTokenId;

        // Mint the options contracts and claim token
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = tokenId;
        tokens[1] = claimTokenId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = 1;

        bytes memory data = new bytes(0);

        // Send tokens to writer
        _batchMint(msg.sender, tokens, amounts, data);

        // Store info about the claim
        tokenType[claimTokenId] = Type.Claim;
        claim[claimTokenId] = Claim({
            option: tokenId,
            amountWritten: amount,
            amountExercised: 0,
            claimed: false
        });

        // TODO(Emit event about the writing)
        // Increment the next token ID
        ++_nextTokenId;
    }

    // TODO(Exercise option)

    // TODO(Redeem claim)

    // TODO(Get info about options contract)

    // TODO(Get info about a claim)
}
