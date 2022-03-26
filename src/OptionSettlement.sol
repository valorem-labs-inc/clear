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

// TODO(Consider converting require strings to errors)
// TODO(Branch later for non harmony VRF support)
// TODO(Interface file to interact without looking at the internals)
// TODO(Event design, architecture, implementation)
// TODO(Adding a fee sweep mechanism rather than on every operation would save gas)
// TODO(DRY code)
// TODO(Optimize)

// @notice This protocol does not support rebase tokens, or fee on transfer tokens

// @dev This enumeration is used to determine the type of an ERC1155 subtoken in the engine.
enum Type {
    None,
    Option,
    Claim
}

// @dev This struct contains the data about an options chain associated with an ERC-1155 token.
struct Option {
    // The underlying asset to be received
    address underlyingAsset;
    // The timestamp after which this option may be exercised
    uint40 exerciseTimestamp;
    // The timestamp before which this option must be exercised
    uint40 expiryTimestamp;
    // The address of the asset needed for exercise
    address exerciseAsset;
    // The amount of the underlying asset contained within an option contract of this type
    uint96 underlyingAmount;
    // Random seed created at the time of option chain creation
    uint160 settlementSeed;
    // The amount of the exercise asset required to exercise this option
    uint96 exerciseAmount;
}

// @dev This struct contains the data about a claim ERC-1155 NFT associated with an option chain.
struct Claim {
    // Which option was written
    uint256 option;
    // These are 1:1 contracts with the underlying Option struct
    // The number of contracts written in this claim
    uint112 amountWritten;
    // The amount of contracts assigned for exercise to this claim
    uint112 amountExercised;
    // The two amounts above along with the option info, can be used to calculate the underlying assets
    bool claimed;
}

// TODO(Gas optimized fees struct?)

contract OptionSettlementEngine is ERC1155 {
    uint8 public immutable feeBps = 5;

    address public feeTo = 0x36273803306a3C22bc848f8Db761e974697ece0d;

    // To increment the next available token id
    uint256 public nextTokenId;

    // Is this an option or a claim?
    mapping(uint256 => Type) public tokenType;

    // Accessor for Option contract details
    mapping(uint256 => Option) public option;

    // The list of claims for an option
    mapping(uint256 => uint256[]) internal optionToClaims;

    // TODO(Should this be a public uint256 lookup of the token id if exists?)
    // If so, we need to reserve token 0 above
    // This is used to check if an Option chain already exists
    mapping(bytes32 => bool) public chainMap;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) public claim;

    mapping(address => uint256) public feeBalance;

    address[] public feeBalanceTokens;

    function setFeeTo(address newFeeTo) public {
        require(msg.sender == feeTo, "Must be present fee collector.");
        feeTo = newFeeTo;
    }

    // TODO(Consider keeper here)
    // TODO(Test)
    function sweepFees(address[] memory tokens) public {
        unchecked {
            uint256 numTokens = tokens.length;
            for (uint256 i = 0; i < numTokens; i++) {
                uint256 fee = feeBalance[tokens[i]];
                // TODO(Leave 1 wei here as a gas optimization)
                if (fee > 0) {
                    SafeTransferLib.safeTransfer(ERC20(tokens[i]), feeTo, fee);
                    feeBalance[tokens[i]] = 0;
                }
            }
        }
        // TODO(Emit event about fees collected)
    }

    // https://docs.harmony.one/home/developers/tools/harmony-vrf
    function vrf() internal view returns (bytes32 result) {
        uint256[1] memory bn;
        bn[0] = block.number;
        assembly {
            let memPtr := mload(0x40)
            if iszero(staticcall(not(0), 0xff, bn, 0x20, memPtr, 0x20)) {
                invalid()
            }
            result := mload(memPtr)
        }
    }

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

    function newChain(Option memory optionInfo)
        external
        returns (uint256 tokenId)
    {
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

        // Get random settlement seed from VRF
        optionInfo.settlementSeed = uint160(uint256(vrf()));

        // Create option token and increment
        tokenType[nextTokenId] = Type.Option;

        // Check that both tokens are ERC20 by instantiating them and checking supply
        ERC20 underlyingToken = ERC20(optionInfo.underlyingAsset);
        ERC20 exerciseToken = ERC20(optionInfo.exerciseAsset);

        // Check total supplies and ensure the option will be exercisable
        require(
            underlyingToken.totalSupply() >= optionInfo.underlyingAmount,
            "Invalid Supply"
        );
        require(
            exerciseToken.totalSupply() >= optionInfo.exerciseAmount,
            "Invalid Supply"
        );

        option[nextTokenId] = optionInfo;

        // TODO(This should emit an event about the creation for indexing in a graph)

        tokenId = nextTokenId;

        // Increment the next token id to be used
        ++nextTokenId;
        chainMap[chainKey] = true;
    }

    function write(uint256 optionId, uint112 amount) external {
        require(tokenType[optionId] == Type.Option, "Token is not an option");

        Option storage optionRecord = option[optionId];

        require(
            optionRecord.expiryTimestamp > block.timestamp,
            "Can't write expired options"
        );

        uint256 rx_amount = amount * optionRecord.underlyingAmount;
        uint256 fee = ((rx_amount / 10000) * feeBps);
        address underlyingAsset = optionRecord.underlyingAsset;

        // Transfer the requisite underlying asset
        SafeTransferLib.safeTransferFrom(
            ERC20(underlyingAsset),
            msg.sender,
            address(this),
            (rx_amount + fee)
        );

        uint256 claimId = nextTokenId;

        // Mint the options contracts and claim token
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = optionId;
        tokens[1] = claimId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint256(amount);
        amounts[1] = 1;

        bytes memory data = new bytes(0);

        // Send tokens to writer
        _batchMint(msg.sender, tokens, amounts, data);

        // Store info about the claim
        tokenType[claimId] = Type.Claim;
        claim[claimId] = Claim({
            option: optionId,
            amountWritten: amount,
            amountExercised: 0,
            claimed: false
        });
        optionToClaims[optionId].push(claimId);

        // TODO(Emit event about fees accrued)
        feeBalance[underlyingAsset] += fee;

        // TODO(Emit event about the writing)
        // Increment the next token ID
        ++nextTokenId;
    }

    function assignExercise(
        uint256 optionId,
        uint112 amount,
        uint160 settlementSeed
    ) internal {
        // TODO(Fuzz this in testing and flush out any bugs)
        // Initial storage pointer
        Claim storage claimRecord;

        // Number of claims enqueued for this option
        uint256 claimsLen = optionToClaims[optionId].length;

        require(claimsLen > 0, "No claims to assign.");

        // Counter for randomness
        uint256 i;

        // To keep track of the slot to overwrite
        uint256 overwrite;

        // Last index in the claims list
        uint256 lastIndex;

        // The new length for the claims list
        uint256 newLen;

        // While there are still options to exercise
        while (amount > 0) {
            // Get the claim number to assign
            uint256 claimNum;
            if (claimsLen == 1) {
                lastIndex = 0;
                claimNum = optionToClaims[optionId][lastIndex];
            } else {
                lastIndex = settlementSeed % claimsLen;
                claimNum = optionToClaims[optionId][lastIndex];
            }

            claimRecord = claim[claimNum];

            uint112 amountWritten = claimRecord.amountWritten;
            if (amountWritten <= amount) {
                amount -= amountWritten;
                claimRecord.amountExercised = amountWritten;
                // We pop the end off and overwrite the old slot
            } else {
                claimRecord.amountExercised = amount;
                amount = 0;
            }
            newLen = claimsLen - 1;
            if (newLen > 0) {
                overwrite = optionToClaims[optionId][newLen];
                // Would be nice if I could pop onto the stack here
                optionToClaims[optionId].pop();
                claimsLen = newLen;
                optionToClaims[optionId][lastIndex] = overwrite;
            } else {
                optionToClaims[optionId].pop();
            }

            // Increment for the next loop
            settlementSeed = uint160(
                uint256(keccak256(abi.encode(settlementSeed, i)))
            );
            i++;
        }

        // Update the settlement seed in storage for the next exercise.
        option[optionId].settlementSeed = settlementSeed;
    }

    function exercise(uint256 optionId, uint112 amount) external {
        require(tokenType[optionId] == Type.Option, "Token is not an option");

        Option storage optionRecord = option[optionId];

        // Require that we have reached the exercise timestamp

        require(
            optionRecord.exerciseTimestamp <= block.timestamp,
            "Too early to exercise"
        );
        uint256 rx_amount = optionRecord.exerciseAmount * amount;
        uint256 tx_amount = optionRecord.underlyingAmount * amount;
        uint256 fee = ((rx_amount / 10000) * feeBps);
        address exerciseAsset = optionRecord.exerciseAsset;

        // Transfer in the requisite exercise asset
        SafeTransferLib.safeTransferFrom(
            ERC20(optionRecord.exerciseAsset),
            msg.sender,
            address(this),
            (rx_amount + fee)
        );

        // Transfer out the underlying
        SafeTransferLib.safeTransfer(
            ERC20(optionRecord.underlyingAsset),
            msg.sender,
            tx_amount
        );

        assignExercise(optionId, amount, optionRecord.settlementSeed);

        // TODO(Emit event about fees accrued)
        feeBalance[exerciseAsset] += fee;

        _burn(msg.sender, optionId, amount);
        // TODO(Emit events for indexing and frontend)
    }

    function redeem(uint256 claimId) external {
        require(tokenType[claimId] == Type.Claim, "Token is not an claim");

        uint256 balance = this.balanceOf(msg.sender, claimId);
        require(balance == 1, "no claim token");

        Claim storage claimRecord = claim[claimId];

        require(!claimRecord.claimed, "Already Claimed");

        uint256 optionId = claimRecord.option;
        Option storage optionRecord = option[optionId];

        require(
            optionRecord.expiryTimestamp <= block.timestamp,
            "Not expired yet"
        );

        uint256 exerciseAmount = optionRecord.exerciseAmount *
            claimRecord.amountExercised;
        uint256 underlyingAmount = (optionRecord.underlyingAmount *
            (claimRecord.amountWritten - claimRecord.amountExercised));

        if (exerciseAmount > 0) {
            SafeTransferLib.safeTransfer(
                ERC20(optionRecord.exerciseAsset),
                msg.sender,
                exerciseAmount
            );
        }

        if (underlyingAmount > 0) {
            SafeTransferLib.safeTransfer(
                ERC20(optionRecord.underlyingAsset),
                msg.sender,
                underlyingAmount
            );
        }

        claimRecord.claimed = true;

        // TODO(Emit events for indexing and frontend)

        _burn(msg.sender, claimId, 1);
    }

    function underlying(uint256 tokenId) external view {
        require(tokenType[tokenId] != Type.None, "Token does not exist");
        // TODO(Get info about underlying assets)
        // TODO(Get info about options contract)
        // TODO(Get info about a claim)
    }
}
