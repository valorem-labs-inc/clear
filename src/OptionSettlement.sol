// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "base64/Base64.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC1155.sol";
import "./interfaces/IOptionSettlementEngine.sol";
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

// TODO(Consider converting require strings to errors for gas savings)
// TODO(Branch later for non harmony VRF support)
// TODO(Event design, architecture, implementation)
// TODO(DRY code)
// TODO(Optimize)
// TODO(Gas optimized fees struct?)

// @notice This settlement protocol does not support rebase tokens, or fee on transfer tokens

contract OptionSettlementEngine is IOptionSettlementEngine, ERC1155 {
    // The protocol fee
    uint8 public immutable feeBps = 5;

    // The address fees accrue to
    address public feeTo = 0x36273803306a3C22bc848f8Db761e974697ece0d;

    // The token type for a given tokenId
    mapping(uint256 => Type) public tokenType;

    // Fee balance for a given token
    mapping(address => uint256) public feeBalance;

    // Input hash to get option token ID if it exists
    mapping(bytes32 => uint256) public hashToOptionToken;

    // The next token id
    uint256 internal nextTokenId = 1;

    // The list of claims for an option
    mapping(uint256 => uint256[]) internal unexercisedClaimsByOption;

    // Accessor for Option contract details
    mapping(uint256 => Option) internal _option;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) internal _claim;

    function option(uint256 tokenId)
        external
        view
        returns (Option memory optionInfo)
    {
        optionInfo = _option[tokenId];
    }

    function claim(uint256 tokenId)
        external
        view
        returns (Claim memory claimInfo)
    {
        claimInfo = _claim[tokenId];
    }

    function setFeeTo(address newFeeTo) public {
        require(msg.sender == feeTo, "Must be present fee collector.");
        feeTo = newFeeTo;
    }

    function sweepFees(address[] memory tokens) public {
        address sendFeeTo = feeTo;
        address token;
        uint256 fee;
        uint256 sweep;
        uint256 numTokens = tokens.length;

        unchecked {
            for (uint256 i = 0; i < numTokens; i++) {
                // Get the token and balance to sweep
                token = tokens[i];

                fee = feeBalance[token];
                // Leave 1 wei here as a gas optimization
                if (fee > 1) {
                    sweep = feeBalance[token] - 1;
                    SafeTransferLib.safeTransfer(
                        ERC20(token),
                        sendFeeTo,
                        sweep
                    );
                    feeBalance[token] = 1;
                    emit FeeSwept(token, sendFeeTo, sweep);
                }
            }
        }
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
        returns (uint256 optionId)
    {
        // Ensure settlement seed is 0
        optionInfo.settlementSeed = 0;

        // Check that a duplicate chain doesn't exist
        bytes32 chainKey = keccak256(abi.encode(optionInfo));

        // If it does, revert
        require(hashToOptionToken[chainKey] == 0, "This option chain exists");

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

        _option[nextTokenId] = optionInfo;

        optionId = nextTokenId;

        // Increment the next token id to be used
        ++nextTokenId;
        hashToOptionToken[chainKey] = optionId;

        emit NewChain(
            optionId,
            optionInfo.exerciseAsset,
            optionInfo.underlyingAsset,
            optionInfo.exerciseAmount,
            optionInfo.underlyingAmount,
            optionInfo.exerciseTimestamp,
            optionInfo.expiryTimestamp
        );
    }

    function write(uint256 optionId, uint112 amount)
        external
        returns (uint256 claimId)
    {
        require(tokenType[optionId] == Type.Option, "Token is not an option");

        Option storage optionRecord = _option[optionId];

        require(
            optionRecord.expiryTimestamp > block.timestamp,
            "Can't write expired options"
        );

        uint256 rxAmount = amount * optionRecord.underlyingAmount;
        uint256 fee = ((rxAmount / 10000) * feeBps);
        address underlyingAsset = optionRecord.underlyingAsset;

        // Transfer the requisite underlying asset
        SafeTransferLib.safeTransferFrom(
            ERC20(underlyingAsset),
            msg.sender,
            address(this),
            (rxAmount + fee)
        );

        claimId = nextTokenId;

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
        _claim[claimId] = Claim({
            option: optionId,
            amountWritten: amount,
            amountExercised: 0,
            claimed: false
        });
        unexercisedClaimsByOption[optionId].push(claimId);

        feeBalance[underlyingAsset] += fee;

        // Increment the next token ID
        ++nextTokenId;

        emit FeeAccrued(underlyingAsset, msg.sender, fee);
        emit OptionsWritten(optionId, msg.sender, claimId, amount);
    }

    function assignExercise(
        uint256 optionId,
        uint112 amount,
        uint160 settlementSeed
    ) internal {
        // Initial storage pointer
        Claim storage claimRecord;

        // Number of claims enqueued for this option
        uint256 claimsLen = unexercisedClaimsByOption[optionId].length;

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
                claimNum = unexercisedClaimsByOption[optionId][lastIndex];
            } else {
                lastIndex = settlementSeed % claimsLen;
                claimNum = unexercisedClaimsByOption[optionId][lastIndex];
            }

            claimRecord = _claim[claimNum];

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
                overwrite = unexercisedClaimsByOption[optionId][newLen];
                // Would be nice if I could pop onto the stack here
                unexercisedClaimsByOption[optionId].pop();
                claimsLen = newLen;
                unexercisedClaimsByOption[optionId][lastIndex] = overwrite;
            } else {
                unexercisedClaimsByOption[optionId].pop();
            }
            // TODO(Emit event about assignment?)

            // Increment for the next loop
            settlementSeed = uint160(
                uint256(keccak256(abi.encode(settlementSeed, i)))
            );
            i++;
        }

        // Update the settlement seed in storage for the next exercise.
        _option[optionId].settlementSeed = settlementSeed;
    }

    function exercise(uint256 optionId, uint112 amount) external {
        require(tokenType[optionId] == Type.Option, "Token is not an option");

        Option storage optionRecord = _option[optionId];

        // Require that we have reached the exercise timestamp
        require(
            optionRecord.exerciseTimestamp <= block.timestamp,
            "Too early to exercise"
        );

        uint256 rxAmount = optionRecord.exerciseAmount * amount;
        uint256 txAmount = optionRecord.underlyingAmount * amount;
        uint256 fee = ((rxAmount / 10000) * feeBps);
        address exerciseAsset = optionRecord.exerciseAsset;

        // Transfer in the requisite exercise asset
        SafeTransferLib.safeTransferFrom(
            ERC20(optionRecord.exerciseAsset),
            msg.sender,
            address(this),
            (rxAmount + fee)
        );

        // Transfer out the underlying
        SafeTransferLib.safeTransfer(
            ERC20(optionRecord.underlyingAsset),
            msg.sender,
            txAmount
        );

        assignExercise(optionId, amount, optionRecord.settlementSeed);

        feeBalance[exerciseAsset] += fee;

        _burn(msg.sender, optionId, amount);

        emit FeeAccrued(exerciseAsset, msg.sender, fee);
        emit OptionsExercised(optionId, msg.sender, amount);
    }

    function redeem(uint256 claimId) external {
        require(tokenType[claimId] == Type.Claim, "Token is not an claim");

        uint256 balance = this.balanceOf(msg.sender, claimId);
        require(balance == 1, "no claim token");

        Claim storage claimRecord = _claim[claimId];

        require(!claimRecord.claimed, "Already Claimed");

        uint256 optionId = claimRecord.option;
        Option storage optionRecord = _option[optionId];

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

        emit ClaimRedeemed(claimId, msg.sender);
    }

    function underlying(uint256 tokenId)
        external
        view
        returns (Underlying memory underlyingPositions)
    {
        // TODO(Get info about underlying assets)
        // TODO(Get info about options contract)
        // TODO(Get info about a claim)
        require(tokenType[tokenId] != Type.None, "Token does not exist");
        underlyingPositions = Underlying({
            underlyingAsset: address(0),
            underlyingPosition: 0,
            exerciseAsset: address(0),
            exercisePosition: 0
        });
    }
}
