// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "base64/Base64.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC1155.sol";
import "./interfaces/IOptionSettlementEngine.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./TokenURIGenerator.sol";

/**
 * Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, options.
 * All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
 * ERC-20 exercise asset using a pseudorandom number per unique option type for fair settlement. Options contracts
 * are issued as fungible ERC-1155 tokens, with each token representing a contract. Option writers are additionally issued
 * an ERC-1155 NFT representing a lot of contracts written for claiming collateral and exercise assignment. This design
 * eliminates the need for market price oracles, and allows for permission-less writing, and gas efficient transfer, of
 * a broad swath of traditional options.
 */

// @notice This settlement protocol does not support rebase tokens, or fee on transfer tokens

contract OptionSettlementEngine is ERC1155, IOptionSettlementEngine {
    // The protocol fee
    uint8 public immutable feeBps = 5;

    // The address fees accrue to
    address public feeTo = 0x36273803306a3C22bc848f8Db761e974697ece0d;

    // Fee balance for a given token
    mapping(address => uint256) public feeBalance;

    // The list of claims for an option
    mapping(uint160 => uint256[]) internal unexercisedClaimsByOption;

    // Accessor for Option contract details
    mapping(uint160 => Option) internal _option;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) internal _claim;

    /// @inheritdoc IOptionSettlementEngine
    function option(uint256 tokenId) external view returns (Option memory optionInfo) {
        // TODO: Revert if claim IDX is specified?
        (uint160 optionId,) = getDecodedIdComponents(tokenId);
        optionInfo = _option[optionId];
    }

    /// @inheritdoc IOptionSettlementEngine
    function claim(uint256 tokenId) external view returns (Claim memory claimInfo) {
        claimInfo = _claim[tokenId];
    }

    /// @inheritdoc IOptionSettlementEngine
    function tokenType(uint256 tokenId) external pure returns (Type) {
        (, uint96 claimIdx) = getDecodedIdComponents(tokenId);
        // TODO: should we do a read here and ensure the token exists?
        if (claimIdx == 0) {
            return Type.Option;
        }
        return Type.Claim;
    }

    /// @inheritdoc IOptionSettlementEngine
    function setFeeTo(address newFeeTo) public {
        if (msg.sender != feeTo) {
            revert AccessControlViolation(msg.sender, feeTo);
        }
        if (newFeeTo == address(0)) {
            revert InvalidFeeToAddress(newFeeTo);
        }
        feeTo = newFeeTo;
    }

    /// @inheritdoc IOptionSettlementEngine
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
                    sweep = fee - 1;
                    feeBalance[token] = 1;
                    SafeTransferLib.safeTransfer(ERC20(token), sendFeeTo, sweep);
                    emit FeeSwept(token, sendFeeTo, sweep);
                }
            }
        }
    }

    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        Option memory optionInfo;
        (uint160 optionId, uint96 claimId) = getDecodedIdComponents(tokenId);
        optionInfo = _option[optionId];

        if (optionInfo.underlyingAsset == address(0x0)) {
            revert TokenNotFound(tokenId);
        }

        Type _type = claimId == 0 ? Type.Option : Type.Claim;

        TokenURIGenerator.TokenURIParams memory params = TokenURIGenerator.TokenURIParams({
            underlyingAsset: optionInfo.underlyingAsset,
            underlyingSymbol: ERC20(optionInfo.underlyingAsset).symbol(),
            exerciseAsset: optionInfo.exerciseAsset,
            exerciseSymbol: ERC20(optionInfo.exerciseAsset).symbol(),
            exerciseTimestamp: optionInfo.exerciseTimestamp,
            expiryTimestamp: optionInfo.expiryTimestamp,
            underlyingAmount: optionInfo.underlyingAmount,
            exerciseAmount: optionInfo.exerciseAmount,
            tokenType: _type
        });

        return TokenURIGenerator.constructTokenURI(params);
    }

    /// @inheritdoc IOptionSettlementEngine
    function newOptionType(Option memory optionInfo) external returns (uint256 optionId) {
        // Ensure settlement seed is 0
        optionInfo.settlementSeed = 0;

        // Check that a duplicate option type doesn't exist
        bytes20 optionHash = bytes20(keccak256(abi.encode(optionInfo)));
        uint160 optionKey = uint160(optionHash);
        optionId = uint256(optionKey) << 96;

        // If it does, revert
        if (isOptionInitialized(optionKey)) {
            revert OptionsTypeExists(optionId);
        }

        // Make sure that expiry is at least 24 hours from now
        if (optionInfo.expiryTimestamp < (block.timestamp + 86400)) {
            revert ExpiryTooSoon(optionId, optionInfo.expiryTimestamp);
        }

        // Ensure the exercise window is at least 24 hours
        if (optionInfo.expiryTimestamp < (optionInfo.exerciseTimestamp + 86400)) {
            revert ExerciseWindowTooShort();
        }

        // The exercise and underlying assets can't be the same
        if (optionInfo.exerciseAsset == optionInfo.underlyingAsset) {
            revert InvalidAssets(optionInfo.exerciseAsset, optionInfo.underlyingAsset);
        }

        // Use the optionKey to seed entropy
        optionInfo.settlementSeed = optionKey;
        optionInfo.nextClaimId = 1;

        // TODO(Is this check really needed?)
        // Check that both tokens are ERC20 by instantiating them and checking supply
        ERC20 underlyingToken = ERC20(optionInfo.underlyingAsset);
        ERC20 exerciseToken = ERC20(optionInfo.exerciseAsset);

        // Check total supplies and ensure the option will be exercisable
        if (
            underlyingToken.totalSupply() < optionInfo.underlyingAmount
                || exerciseToken.totalSupply() < optionInfo.exerciseAmount
        ) {
            revert InvalidAssets(optionInfo.underlyingAsset, optionInfo.exerciseAsset);
        }

        _option[optionKey] = optionInfo;

        emit NewOptionType(
            optionId,
            optionInfo.exerciseAsset,
            optionInfo.underlyingAsset,
            optionInfo.exerciseAmount,
            optionInfo.underlyingAmount,
            optionInfo.exerciseTimestamp,
            optionInfo.expiryTimestamp,
            optionInfo.nextClaimId
            );
    }

    /// @inheritdoc IOptionSettlementEngine
    function write(uint256 optionId, uint112 amount) external returns (uint256 claimId) {
        /// supplying claimId as 0 to the overloaded write signifies that a new
        /// claim NFT should be minted for the options lot, rather than being added
        /// as an existing claim.
        return write(optionId, amount, 0);
    }

    /// @inheritdoc IOptionSettlementEngine
    function write(uint256 optionId, uint112 amount, uint256 claimId) public returns (uint256) {
        (uint160 _optionIdU160b, uint96 _optionIdL96b) = getDecodedIdComponents(optionId);

        // optionId must be zero in lower 96b for provided option Id
        if (_optionIdL96b != 0) {
            revert InvalidOption(optionId);
        }

        // claim provided must match the option provided
        if (claimId != 0 && ((claimId >> 96) != (optionId >> 96))) {
            revert EncodedOptionIdInClaimIdDoesNotMatchProvidedOptionId(claimId, optionId);
        }

        if (amount == 0) {
            revert AmountWrittenCannotBeZero();
        }

        Option storage optionRecord = _option[_optionIdU160b];

        uint40 expiry = optionRecord.expiryTimestamp;
        if (expiry == 0) {
            revert InvalidOption(_optionIdU160b);
        }
        if (expiry <= block.timestamp) {
            revert ExpiredOption(uint256(_optionIdU160b) << 96, expiry);
        }

        if (optionRecord.expiryTimestamp <= block.timestamp) {
            revert ExpiredOption(uint256(_optionIdU160b) << 96, optionRecord.expiryTimestamp);
        }

        uint256 rxAmount = amount * optionRecord.underlyingAmount;
        uint256 fee = ((rxAmount / 10000) * feeBps);
        address underlyingAsset = optionRecord.underlyingAsset;

        feeBalance[underlyingAsset] += fee;

        emit FeeAccrued(underlyingAsset, msg.sender, fee);
        emit OptionsWritten(optionId, msg.sender, claimId, amount);

        uint256 mintClaimNft = 0;

        if (claimId == 0) {
            // create new claim
            // Increment the next token ID
            uint96 claimIndex = optionRecord.nextClaimId++;
            claimId = getTokenId(_optionIdU160b, claimIndex);
            // Store info about the claim
            _claim[claimId] = Claim({amountWritten: amount, amountExercised: 0, claimed: false});
            unexercisedClaimsByOption[_optionIdU160b].push(claimId);
            mintClaimNft = 1;
        } else {
            // check ownership of claim
            uint256 balance = balanceOf[msg.sender][claimId];
            if (balance != 1) {
                revert CallerDoesNotOwnClaimId(claimId);
            }

            // retrieve claim
            Claim storage existingClaim = _claim[claimId];

            if (existingClaim.claimed) {
                revert AlreadyClaimed(claimId);
            }

            existingClaim.amountWritten += amount;
        }

        // Mint the options contracts and claim token
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = optionId;
        tokens[1] = claimId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = mintClaimNft;

        bytes memory data = new bytes(0);

        // Send tokens to writer
        _batchMint(msg.sender, tokens, amounts, data);

        // Transfer the requisite underlying asset
        SafeTransferLib.safeTransferFrom(ERC20(underlyingAsset), msg.sender, address(this), (rxAmount + fee));

        return claimId;
    }

    function assignExercise(uint160 optionId, uint96 claimsLen, uint112 amount, uint160 settlementSeed) internal {
        // Number of claims enqueued for this option
        if (claimsLen == 0) {
            revert NoClaims(optionId);
        }

        // Initial storage pointer
        Claim storage claimRecord;

        // Counter for randomness
        uint256 i;

        // To keep track of the slot to overwrite
        uint256 overwrite;

        // Last index in the claims list
        uint256 lastIndex;

        // The new length for the claims list
        uint96 newLen;

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

            uint112 amountAvailiable = claimRecord.amountWritten - claimRecord.amountExercised;
            uint112 amountPresentlyExercised;
            if (amountAvailiable < amount) {
                amount -= amountAvailiable;
                amountPresentlyExercised = amountAvailiable;
                // We pop the end off and overwrite the old slot

                newLen = claimsLen - 1;
                unexercisedClaimsByOption[optionId].pop();
                if (newLen > 0) {
                    overwrite = unexercisedClaimsByOption[optionId][newLen];
                    // Would be nice if I could pop onto the stack here
                    claimsLen = newLen;
                    unexercisedClaimsByOption[optionId][lastIndex] = overwrite;
                }
            } else {
                amountPresentlyExercised = amount;
                amount = 0;
            }

            claimRecord.amountExercised += amountPresentlyExercised;
            emit ExerciseAssigned(claimNum, optionId, amountPresentlyExercised);

            // Increment for the next loop
            settlementSeed = uint160(uint256(keccak256(abi.encode(settlementSeed, i))));
            i++;
        }

        // Update the settlement seed in storage for the next exercise.
        _option[optionId].settlementSeed = settlementSeed;
    }

    /// @inheritdoc IOptionSettlementEngine
    function exercise(uint256 optionId, uint112 amount) external {
        (uint160 _optionId, uint96 claimIdx) = getDecodedIdComponents(optionId);

        // option ID should be specified without claim in lower 96b
        if (claimIdx != 0) {
            revert InvalidOption(optionId);
        }

        Option storage optionRecord = _option[_optionId];
        // retrieve the number of claims from the option record
        claimIdx = optionRecord.nextClaimId - 1;

        if (optionRecord.expiryTimestamp <= block.timestamp) {
            revert ExpiredOption(optionId, optionRecord.expiryTimestamp);
        }
        // Require that we have reached the exercise timestamp
        if (optionRecord.exerciseTimestamp >= block.timestamp) {
            revert ExerciseTooEarly(optionId, optionRecord.exerciseTimestamp);
        }

        uint256 rxAmount = optionRecord.exerciseAmount * amount;
        uint256 txAmount = optionRecord.underlyingAmount * amount;
        uint256 fee = ((rxAmount / 10000) * feeBps);
        address exerciseAsset = optionRecord.exerciseAsset;

        assignExercise(_optionId, claimIdx, amount, optionRecord.settlementSeed);

        feeBalance[exerciseAsset] += fee;

        _burn(msg.sender, optionId, amount);

        // Transfer in the requisite exercise asset
        SafeTransferLib.safeTransferFrom(ERC20(exerciseAsset), msg.sender, address(this), (rxAmount + fee));

        // Transfer out the underlying
        SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, txAmount);

        emit FeeAccrued(exerciseAsset, msg.sender, fee);
        emit OptionsExercised(optionId, msg.sender, amount);
    }

    /// @inheritdoc IOptionSettlementEngine
    function redeem(uint256 claimId) external {
        (uint160 optionId, uint96 claimIdx) = getDecodedIdComponents(claimId);

        if (claimIdx == 0) {
            revert InvalidClaim(claimId);
        }

        uint256 balance = this.balanceOf(msg.sender, claimId);

        if (balance != 1) {
            revert CallerDoesNotOwnClaimId(claimId);
        }

        Claim storage claimRecord = _claim[claimId];

        if (claimRecord.claimed) {
            revert AlreadyClaimed(claimId);
        }

        Option storage optionRecord = _option[optionId];

        if (optionRecord.expiryTimestamp > block.timestamp) {
            revert ClaimTooSoon(claimId, optionRecord.expiryTimestamp);
        }

        uint256 exerciseAmount = optionRecord.exerciseAmount * claimRecord.amountExercised;
        uint256 underlyingAmount =
            (optionRecord.underlyingAmount * (claimRecord.amountWritten - claimRecord.amountExercised));

        claimRecord.claimed = true;

        _burn(msg.sender, claimId, 1);

        if (exerciseAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.exerciseAsset), msg.sender, exerciseAmount);
        }

        if (underlyingAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, underlyingAmount);
        }

        // TODO: stdize emissions vis a vis claim index, option id, token id
        emit ClaimRedeemed(
            claimId,
            optionId,
            msg.sender,
            optionRecord.exerciseAsset,
            optionRecord.underlyingAsset,
            uint96(exerciseAmount),
            uint96(underlyingAmount)
            );
    }

    /// @inheritdoc IOptionSettlementEngine
    function underlying(uint256 tokenId) external view returns (Underlying memory underlyingPositions) {
        (uint160 optionId, uint96 claimIdx) = getDecodedIdComponents(tokenId);

        if (!isOptionInitialized(optionId)) {
            revert TokenNotFound(tokenId);
        }

        // token ID is an option
        if (claimIdx == 0) {
            Option storage optionRecord = _option[optionId];
            bool expired = (optionRecord.expiryTimestamp > block.timestamp);
            underlyingPositions = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: expired ? int256(0) : int256(uint256(optionRecord.underlyingAmount)),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: expired ? int256(0) : -int256(uint256(optionRecord.exerciseAmount))
            });
        } else {
            // token ID is a claim
            Claim storage claimRecord = _claim[tokenId];
            Option storage optionRecord = _option[optionId];
            uint256 exerciseAmount = optionRecord.exerciseAmount * claimRecord.amountExercised;
            uint256 underlyingAmount =
                (optionRecord.underlyingAmount * (claimRecord.amountWritten - claimRecord.amountExercised));
            underlyingPositions = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: int256(underlyingAmount),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: int256(exerciseAmount)
            });
        }
    }

    // **********************************************************************
    //                    TOKEN ID ENCODING HELPERS
    // **********************************************************************
    /**
     * @dev Claim and option type ids are encoded as follows:
     * (MSb)
     * [160b hash of option data structure]
     * [96b encoding of claim id]
     * (LSb)
     * This function decodes a supplied id.
     * @return optionId claimId The decoded components of the id as described above,
     * padded as required.
     */
    function getDecodedIdComponents(uint256 id) public pure returns (uint160 optionId, uint96 claimId) {
        // grab lower 96b of id for claim id
        uint256 claimIdMask = 0xFFFFFFFFFFFFFFFFFFFFFFFF;

        // move hash to LSB to fit into uint160
        optionId = uint160(id >> 96);
        claimId = uint96(id & claimIdMask);
    }

    function getOptionFromEncodedId(uint256 id) public view returns (Option memory) {
        (uint160 optionId,) = getDecodedIdComponents(id);
        return _option[optionId];
    }

    function getTokenId(uint160 optionId, uint96 claimIndex) public pure returns (uint256 claimId) {
        claimId |= (uint256(optionId) << 96);
        claimId |= uint256(claimIndex);
    }

    function isOptionInitialized(uint160 optionId) public view returns (bool) {
        return _option[optionId].underlyingAsset != address(0x0);
    }
}
