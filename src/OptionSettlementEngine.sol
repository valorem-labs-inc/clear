// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "base64/Base64.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC1155.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/utils/FixedPointMathLib.sol";

import "./interfaces/IOptionSettlementEngine.sol";
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

/// @title A settlement engine for options
/// @dev This settlement protocol does not support rebasing, fee-on-transfer, or ERC-777 tokens
/// @author 0xAlcibiades
/// @author Flip-Liquid
/// @author neodaoist
contract OptionSettlementEngine is ERC1155, IOptionSettlementEngine {
    /*//////////////////////////////////////////////////////////////
    //  State variables - Public
    //////////////////////////////////////////////////////////////*/

    /// @notice The protocol fee
    uint8 public immutable feeBps = 5;

    /// @notice Fee balance for a given token
    mapping(address => uint256) public feeBalance;

    /// @notice The address fees accrue to
    address public feeTo;

    /*//////////////////////////////////////////////////////////////
    //  State variables - Internal
    //////////////////////////////////////////////////////////////*/

    /// @notice Accessor for Option contract details
    mapping(uint160 => Option) internal _option;

    /// @notice Accessor for option lot claim ticket details
    mapping(uint256 => OptionLotClaim) internal _claim;

    /// @notice Accessor for buckets of claims grouped by day
    /// @dev This is to enable O(constant) time options exercise. When options are written,
    /// the Claim struct in this mapping is updated to reflect the cumulative amount written
    /// on the day in question. write() will add unexercised options into the bucket
    /// corresponding to the # of days after the option type's creation.
    /// exercise() will randomly assign exercise to a bucket <= the current day.
    mapping(uint160 => OptionsDayBucket[]) internal _claimBucketByOption;

    /// @notice Maintains a mapping from option id to a list of unexercised bucket (indices)
    /// @dev Used during the assignment process to find claim buckets with unexercised
    /// options.
    mapping(uint160 => uint16[]) internal _unexercisedBucketsByOption;

    /// @notice Maps a bucket's index (in _claimBucketByOption) to a boolean indicating
    /// if the bucket has any unexercised options.
    /// @dev Used to determine if a bucket index needs to be added to
    /// _unexercisedBucketsByOption during write(). Set false if a bucket is fully
    /// exercised.
    mapping(uint160 => mapping(uint16 => bool)) internal _doesBucketIndexHaveUnexercisedOptions;

    /// @notice Accessor for mapping a claim id to its ClaimIndices
    mapping(uint256 => OptionLotClaimIndex[]) internal _claimIdToClaimIndexArray;

    /*//////////////////////////////////////////////////////////////
    //  Constructor
    //////////////////////////////////////////////////////////////*/

    /// @notice OptionSettlementEngine constructor
    /// @param _feeTo The address fees accrue to
    constructor(address _feeTo) {
        feeTo = _feeTo;
    }

    /*//////////////////////////////////////////////////////////////
    //  Accessors
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    function option(uint256 tokenId) external view returns (Option memory optionInfo) {
        (uint160 optionKey,) = decodeTokenId(tokenId);
        optionInfo = _option[optionKey];
    }

    /// @inheritdoc IOptionSettlementEngine
    function claim(uint256 tokenId) external view returns (OptionLotClaim memory claimInfo) {
        claimInfo = _claim[tokenId];
    }

    /// @inheritdoc IOptionSettlementEngine
    function underlying(uint256 tokenId) external view returns (Underlying memory underlyingPositions) {
        (uint160 optionKey, uint96 claimNum) = decodeTokenId(tokenId);

        if (!isOptionInitialized(optionKey)) {
            revert TokenNotFound(tokenId);
        }

        Option storage optionRecord = _option[optionKey];

        // token ID is an option
        if (claimNum == 0) {
            bool expired = (optionRecord.expiryTimestamp <= block.timestamp);
            underlyingPositions = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: expired ? int256(0) : int256(uint256(optionRecord.underlyingAmount)),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: expired ? int256(0) : -int256(uint256(optionRecord.exerciseAmount))
            });
        } else {
            // token ID is a claim
            (uint256 amountExerciseAsset, uint256 amountUnderlyingAsset) =
                _getPositionsForClaim(optionKey, tokenId, optionRecord);

            underlyingPositions = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: int256(amountUnderlyingAsset),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: int256(amountExerciseAsset)
            });
        }
    }

    /// @inheritdoc IOptionSettlementEngine
    function tokenType(uint256 tokenId) external pure returns (Type) {
        (, uint96 claimNum) = decodeTokenId(tokenId);
        if (claimNum == 0) {
            return Type.Option;
        }
        return Type.OptionLotClaim;
    }

    /// @inheritdoc IOptionSettlementEngine
    function isOptionInitialized(uint160 optionKey) public view returns (bool) {
        return _option[optionKey].underlyingAsset != address(0x0);
    }

    /*//////////////////////////////////////////////////////////////
    //  Token URI
    //////////////////////////////////////////////////////////////*/

    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        Option memory optionInfo;
        (uint160 optionKey, uint96 claimNum) = decodeTokenId(tokenId);
        optionInfo = _option[optionKey];

        if (optionInfo.underlyingAsset == address(0x0)) {
            revert TokenNotFound(tokenId);
        }

        Type _type = claimNum == 0 ? Type.Option : Type.OptionLotClaim;

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

    /*//////////////////////////////////////////////////////////////
    //  Token ID Encoding
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    function encodeTokenId(uint160 optionKey, uint96 claimNum) public pure returns (uint256 tokenId) {
        tokenId |= (uint256(optionKey) << 96);
        tokenId |= uint256(claimNum);
    }

    /// @inheritdoc IOptionSettlementEngine
    function decodeTokenId(uint256 tokenId) public pure returns (uint160 optionKey, uint96 claimNum) {
        // move key to LSB to fit into uint160
        optionKey = uint160(tokenId >> 96);

        // grab lower 96b of id for claim index
        uint256 claimNumMask = 0xFFFFFFFFFFFFFFFFFFFFFFFF;
        claimNum = uint96(tokenId & claimNumMask);
    }

    /**
     * @notice Return the option for the supplied token id
     * @dev See encodeTokenId() for encoding scheme
     * @param tokenId The token id of the Option
     * @return The stored Option
     */
    function getOptionForTokenId(uint256 tokenId) public view returns (Option memory) {
        (uint160 optionKey,) = decodeTokenId(tokenId);
        return _option[optionKey];
    }

    function getClaimForTokenId(uint256 tokenId) public view returns (OptionLotClaim memory) {
        return _claim[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
    //  Write Options
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    function newOptionType(
        address underlyingAsset,
        uint96 underlyingAmount,
        address exerciseAsset,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) external returns (uint256 optionId) {
        // Check that a duplicate option type doesn't exist
        uint160 optionKey = uint160(
            bytes20(
                keccak256(
                    abi.encode(
                        underlyingAsset,
                        underlyingAmount,
                        exerciseAsset,
                        exerciseAmount,
                        exerciseTimestamp,
                        expiryTimestamp,
                        uint160(0),
                        uint96(0)
                    )
                )
            )
        );
        optionId = uint256(optionKey) << 96;

        // If it does, revert
        if (isOptionInitialized(optionKey)) {
            revert OptionsTypeExists(optionId);
        }

        // Make sure that expiry is at least 24 hours from now
        if (expiryTimestamp < (block.timestamp + 1 days)) {
            revert ExpiryWindowTooShort(expiryTimestamp);
        }

        // Ensure the exercise window is at least 24 hours
        if (expiryTimestamp < (exerciseTimestamp + 1 days)) {
            revert ExerciseWindowTooShort(exerciseTimestamp);
        }

        // The exercise and underlying assets can't be the same
        if (exerciseAsset == underlyingAsset) {
            revert InvalidAssets(exerciseAsset, underlyingAsset);
        }

        // Check that both tokens are ERC20 by instantiating them and checking supply
        ERC20 underlyingToken = ERC20(underlyingAsset);
        ERC20 exerciseToken = ERC20(exerciseAsset);

        // Check total supplies and ensure the option will be exercisable
        if (underlyingToken.totalSupply() < underlyingAmount || exerciseToken.totalSupply() < exerciseAmount) {
            revert InvalidAssets(underlyingAsset, exerciseAsset);
        }

        _option[optionKey] = Option({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp,
            settlementSeed: optionKey,
            nextClaimNum: 1
        });

        emit NewOptionType(
            optionId,
            exerciseAsset,
            underlyingAsset,
            exerciseAmount,
            underlyingAmount,
            exerciseTimestamp,
            expiryTimestamp,
            1
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
        (uint160 optionKey, uint96 decodedClaimNum) = decodeTokenId(optionId);

        // optionId must be zero in lower 96b for provided option Id
        if (decodedClaimNum != 0) {
            revert InvalidOption(optionId);
        }

        // claim provided must match the option provided
        if (claimId != 0 && ((claimId >> 96) != (optionId >> 96))) {
            revert EncodedOptionIdInClaimIdDoesNotMatchProvidedOptionId(claimId, optionId);
        }

        if (amount == 0) {
            revert AmountWrittenCannotBeZero();
        }

        Option storage optionRecord = _option[optionKey];

        uint40 expiry = optionRecord.expiryTimestamp;
        if (expiry == 0) {
            revert InvalidOption(optionKey);
        }
        if (expiry <= block.timestamp) {
            revert ExpiredOption(optionId, expiry);
        }

        uint256 rxAmount = amount * optionRecord.underlyingAmount;
        uint256 fee = ((rxAmount / 10_000) * feeBps);
        address underlyingAsset = optionRecord.underlyingAsset;

        feeBalance[underlyingAsset] += fee;

        emit FeeAccrued(underlyingAsset, msg.sender, fee);
        emit OptionsWritten(optionId, msg.sender, claimId, amount);

        uint256 mintClaimNft = 0;

        if (claimId == 0) {
            // create new claim
            // Increment the next token ID
            uint96 claimNum = optionRecord.nextClaimNum++;
            claimId = encodeTokenId(optionKey, claimNum);
            // Store info about the claim
            _claim[claimId] = OptionLotClaim({amountWritten: amount, claimed: false});
            mintClaimNft = 1;
        } else {
            // check ownership of claim
            uint256 balance = balanceOf[msg.sender][claimId];
            if (balance != 1) {
                revert CallerDoesNotOwnClaimId(claimId);
            }

            // retrieve claim
            OptionLotClaim storage existingClaim = _claim[claimId];

            existingClaim.amountWritten += amount;
        }
        uint16 bucketIndex = _addOrUpdateClaimBucket(optionKey, amount);
        _addOrUpdateClaimIndex(claimId, bucketIndex, amount);

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

    /*//////////////////////////////////////////////////////////////
    //  Exercise Options
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    function exercise(uint256 optionId, uint112 amount) external {
        (uint160 optionKey, uint96 claimNum) = decodeTokenId(optionId);

        // option ID should be specified without claim in lower 96b
        if (claimNum != 0) {
            revert InvalidOption(optionId);
        }

        Option storage optionRecord = _option[optionKey];

        if (optionRecord.expiryTimestamp <= block.timestamp) {
            revert ExpiredOption(optionId, optionRecord.expiryTimestamp);
        }
        // Require that we have reached the exercise timestamp
        if (optionRecord.exerciseTimestamp >= block.timestamp) {
            revert ExerciseTooEarly(optionId, optionRecord.exerciseTimestamp);
        }

        if (this.balanceOf(msg.sender, optionId) < amount) {
            revert CallerHoldsInsufficientOptions(optionId, amount);
        }

        uint256 rxAmount = optionRecord.exerciseAmount * amount;
        uint256 txAmount = optionRecord.underlyingAmount * amount;
        uint256 fee = ((rxAmount / 10_000) * feeBps);
        address exerciseAsset = optionRecord.exerciseAsset;

        _assignExercise(optionKey, optionRecord, amount);

        feeBalance[exerciseAsset] += fee;

        _burn(msg.sender, optionId, amount);

        // Transfer in the requisite exercise asset
        SafeTransferLib.safeTransferFrom(ERC20(exerciseAsset), msg.sender, address(this), (rxAmount + fee));

        // Transfer out the underlying
        SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, txAmount);

        emit FeeAccrued(exerciseAsset, msg.sender, fee);
        emit OptionsExercised(optionId, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
    //  Redeem Claims
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    /// @dev Fair assignment is performed here. After option expiry, any claim holder
    /// seeking to redeem their claim for the underlying and exercise assets will claim
    /// amounts proportional to the per-day amounts written on their options lot (i.e.
    /// the OptionLotClaimIndex data structions) weighted by the ratio of exercised to
    /// unexercised options on each of those days.
    function redeem(uint256 claimId) external {
        (uint160 optionKey, uint96 claimNum) = decodeTokenId(claimId);

        if (claimNum == 0) {
            revert InvalidClaim(claimId);
        }

        uint256 balance = this.balanceOf(msg.sender, claimId);

        if (balance != 1) {
            revert CallerDoesNotOwnClaimId(claimId);
        }

        OptionLotClaim storage claimRecord = _claim[claimId];

        if (claimRecord.claimed) {
            revert AlreadyClaimed(claimId);
        }

        Option storage optionRecord = _option[optionKey];

        if (optionRecord.expiryTimestamp > block.timestamp) {
            revert ClaimTooSoon(claimId, optionRecord.expiryTimestamp);
        }

        (uint256 exerciseAmount, uint256 underlyingAmount) = _getPositionsForClaim(optionKey, claimId, optionRecord);

        claimRecord.claimed = true;

        _burn(msg.sender, claimId, 1);

        if (exerciseAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.exerciseAsset), msg.sender, exerciseAmount);
        }

        if (underlyingAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, underlyingAmount);
        }

        emit ClaimRedeemed(
            claimId,
            optionKey,
            msg.sender,
            optionRecord.exerciseAsset,
            optionRecord.underlyingAsset,
            uint96(exerciseAmount),
            uint96(underlyingAmount)
            );
    }

    /*//////////////////////////////////////////////////////////////
    //  Protocol Admin
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
    //  Internal Helper Functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Performs fair exercise assignment by pseudorandomly selecting a claim
    /// bucket between the intial creation of the option type and "today". The buckets
    /// are then iterated from oldest to newest (looping if we reach "today") if the
    /// exercise amount overflows into another bucket. The seed for the pseudorandom
    /// index is updated accordingly on the option type.
    function _assignExercise(uint160 optionId, Option storage optionRecord, uint112 amount) internal {
        // A bucket of the overall amounts written and exercised for all claims
        // on a given day
        OptionsDayBucket[] storage claimBucketArray = _claimBucketByOption[optionId];
        uint16[] storage unexercisedBucketIndices = _unexercisedBucketsByOption[optionId];
        uint16 unexercisedBucketsMod = uint16(unexercisedBucketIndices.length);
        uint16 unexercisedBucketsIndex = uint16(optionRecord.settlementSeed % unexercisedBucketsMod);
        while (amount > 0) {
            // get the claim bucket to assign
            uint16 bucketIndex = unexercisedBucketIndices[unexercisedBucketsIndex];
            OptionsDayBucket storage claimBucketInfo = claimBucketArray[bucketIndex];

            uint112 amountAvailable = claimBucketInfo.amountWritten - claimBucketInfo.amountExercised;
            uint112 amountPresentlyExercised;
            if (amountAvailable <= amount) {
                amount -= amountAvailable;
                amountPresentlyExercised = amountAvailable;
                // swap and pop, index mgmt
                uint16 overwrite = unexercisedBucketIndices[unexercisedBucketIndices.length - 1];
                unexercisedBucketIndices[unexercisedBucketsIndex] = overwrite;
                unexercisedBucketIndices.pop();
                unexercisedBucketsMod -= 1;
                _doesBucketIndexHaveUnexercisedOptions[optionId][bucketIndex] = false;
            } else {
                amountPresentlyExercised = amount;
                amount = 0;
            }
            claimBucketInfo.amountExercised += amountPresentlyExercised;

            if (amount != 0) {
                unexercisedBucketsIndex = (unexercisedBucketsIndex + 1) % unexercisedBucketsMod;
            }
        }

        // update settlement seed
        optionRecord.settlementSeed =
            uint160(uint256(keccak256(abi.encode(optionRecord.settlementSeed, unexercisedBucketsIndex))));
    }

    /// @dev Help find a given days bucket by calculating days after epoch
    function _getDaysBucket() internal view returns (uint16) {
        return uint16(block.timestamp / 1 days);
    }

    /// @dev Get the amount of exercised and unexercised options for a given claim + day bucket combo
    function _getAmountExercised(OptionLotClaimIndex storage claimIndex, OptionsDayBucket storage claimBucketInfo)
        internal
        view
        returns (uint256 _exercised, uint256 _unexercised)
    {
        // The ratio of exercised to written options in the bucket multiplied by the
        // number of options actaully written in the claim.
        _exercised = FixedPointMathLib.mulDivDown(
            claimBucketInfo.amountExercised, claimIndex.amountWritten, claimBucketInfo.amountWritten
        );

        // The ratio of unexercised to written options in the bucket multiplied by the
        // number of options actually written in the claim.
        _unexercised = FixedPointMathLib.mulDivDown(
            claimBucketInfo.amountWritten - claimBucketInfo.amountExercised,
            claimIndex.amountWritten,
            claimBucketInfo.amountWritten
        );
    }

    /// @dev Get the exercise and underlying amounts for a claim
    function _getPositionsForClaim(uint160 optionId, uint256 claimId, Option storage optionRecord)
        internal
        view
        returns (uint256 exerciseAmount, uint256 underlyingAmount)
    {
        OptionLotClaimIndex[] storage claimIndexArray = _claimIdToClaimIndexArray[claimId];
        for (uint256 i = 0; i < claimIndexArray.length; i++) {
            OptionLotClaimIndex storage claimIndex = claimIndexArray[i];
            OptionsDayBucket storage claimBucketInfo = _claimBucketByOption[optionId][claimIndex.bucketIndex];
            (uint256 amountExercised, uint256 amountUnexercised) = _getAmountExercised(claimIndex, claimBucketInfo);
            exerciseAmount += optionRecord.exerciseAmount * amountExercised;
            underlyingAmount += optionRecord.underlyingAmount * amountUnexercised;
        }
    }

    /// @dev Help with internal options bucket accounting
    function _addOrUpdateClaimBucket(uint160 optionId, uint112 amount) internal returns (uint16) {
        OptionsDayBucket[] storage claimBucketsInfo = _claimBucketByOption[optionId];
        uint16[] storage unexercised = _unexercisedBucketsByOption[optionId];
        OptionsDayBucket storage currentBucket;
        uint16 daysAfterEpoch = _getDaysBucket();
        uint16 bucketIndex = uint16(claimBucketsInfo.length);
        if (claimBucketsInfo.length == 0) {
            // add a new bucket none exist
            claimBucketsInfo.push(OptionsDayBucket(amount, 0, daysAfterEpoch));
            // update _unexercisedBucketsByOption and corresponding index mapping
            _updateUnexercisedBucketIndices(optionId, bucketIndex, unexercised);
            return bucketIndex;
        }

        currentBucket = claimBucketsInfo[bucketIndex - 1];
        if (currentBucket.daysAfterEpoch < daysAfterEpoch) {
            claimBucketsInfo.push(OptionsDayBucket(amount, 0, daysAfterEpoch));
            _updateUnexercisedBucketIndices(optionId, bucketIndex, unexercised);
        } else {
            // Update claim bucket for today
            currentBucket.amountWritten += amount;
            bucketIndex -= 1;

            // This block is executed if a bucket has been previously fully exercised
            // and now more options are being written into it
            if (!_doesBucketIndexHaveUnexercisedOptions[optionId][bucketIndex]) {
                _updateUnexercisedBucketIndices(optionId, bucketIndex, unexercised);
            }
        }

        return bucketIndex;
    }

    /// @dev Help with internal claim bucket accounting
    function _updateUnexercisedBucketIndices(
        uint160 optionId,
        uint16 bucketIndex,
        uint16[] storage unexercisedBucketIndices
    ) internal {
        unexercisedBucketIndices.push(bucketIndex);
        _doesBucketIndexHaveUnexercisedOptions[optionId][bucketIndex] = true;
    }

    /// @dev Help with internal claim bucket accounting
    function _addOrUpdateClaimIndex(uint256 claimId, uint16 bucketIndex, uint112 amount) internal {
        OptionLotClaimIndex storage lastIndex;
        OptionLotClaimIndex[] storage claimIndexArray = _claimIdToClaimIndexArray[claimId];
        uint256 arrayLength = claimIndexArray.length;

        // if no indices have been created previously, create one
        if (arrayLength == 0) {
            claimIndexArray.push(OptionLotClaimIndex({amountWritten: amount, bucketIndex: bucketIndex}));
            return;
        }

        lastIndex = claimIndexArray[arrayLength - 1];

        // create a new claim index if we're writing to a new index
        if (lastIndex.bucketIndex < bucketIndex) {
            claimIndexArray.push(OptionLotClaimIndex({amountWritten: amount, bucketIndex: bucketIndex}));
            return;
        }

        // update the amount written on the existing bucket index
        lastIndex.amountWritten += amount;
    }
}
