// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "base64/Base64.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC1155.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/utils/FixedPointMathLib.sol";

import "./interfaces/IOptionSettlementEngine.sol";
import "./TokenURIGenerator.sol";

/**
 * @title A settlement engine for options on ERC20 tokens
 * @author 0xAlcibiades
 * @author Flip-Liquid
 * @author neodaoist
 * @notice Valorem Options V1 is a DeFi money lego for writing physically
 * settled covered call and covered put options. All Valorem options are fully
 * collateralized with an ERC-20 underlying asset and exercised with an
 * ERC-20 exercise asset using a fair assignment process. Options contracts, or
 * long positions, are issued as fungible ERC-1155 tokens, with each token
 * representing a contract. Option writers are additionally issued an ERC-1155
 * NFT claim, or short position, which is used to claim collateral and for
 * option exercise assignment.
 */
contract OptionSettlementEngine is ERC1155, IOptionSettlementEngine {
    /*//////////////////////////////////////////////////////////////
    //  Immutable/Constant - Private
    //////////////////////////////////////////////////////////////*/

    /// @dev The bit padding for optionKey -> optionId.
    uint8 internal constant OPTION_ID_PADDING = 96;

    /// @dev The mask to mask out a claimKey from a claimId.
    uint96 internal constant CLAIM_NUMBER_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF;

    /*//////////////////////////////////////////////////////////////
    //  Immutable/Constant - Public
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    uint8 public immutable feeBps = 5;

    /*//////////////////////////////////////////////////////////////
    //  State variables - Internal
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Store details about the option, bucket, claim details per option
     * type.
     */
    mapping(uint160 => OptionTypeState) internal optionTypeStates;

    /*//////////////////////////////////////////////////////////////
    //  State variables - Public
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    mapping(address => uint256) public feeBalance;

    /// @inheritdoc IOptionSettlementEngine
    ITokenURIGenerator public tokenURIGenerator;

    /// @inheritdoc IOptionSettlementEngine
    address public feeTo;

    /// @inheritdoc IOptionSettlementEngine
    bool public feesEnabled;

    /*//////////////////////////////////////////////////////////////
    //  Modifiers
    //////////////////////////////////////////////////////////////*/

    /// @notice This modifier restricts function access to the feeTo address.
    modifier onlyFeeTo() {
        if (msg.sender != feeTo) {
            revert AccessControlViolation(msg.sender, feeTo);
        }

        _;
    }

    /*//////////////////////////////////////////////////////////////
    //  Constructor
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructs the OptionSettlementEngine.
     * @param _feeTo The address fees accrue to.
     * @param _tokenURIGenerator The contract address of the token URI generator.
     */
    constructor(address _feeTo, address _tokenURIGenerator) {
        if (_feeTo == address(0) || _tokenURIGenerator == address(0)) {
            revert InvalidAddress(address(0));
        }

        feeTo = _feeTo;
        tokenURIGenerator = ITokenURIGenerator(_tokenURIGenerator);
    }

    /*//////////////////////////////////////////////////////////////
    //  Public/External Views
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptionSettlementEngine
    function option(uint256 tokenId) external view returns (Option memory optionInfo) {
        (uint160 optionKey,) = _decodeTokenId(tokenId);

        if (!isOptionInitialized(optionKey)) {
            revert TokenNotFound(tokenId);
        }

        optionInfo = optionTypeStates[optionKey].option;
    }

    // TODO(Verify/add fuzz assertions)
    /// @inheritdoc IOptionSettlementEngine
    function claim(uint256 claimId) public view returns (Claim memory claimInfo) {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(claimId);

        if (!isClaimInitialized(optionKey, claimKey)) {
            revert TokenNotFound(claimId);
        }

        // This sums up all the claim indices comprising the claim.
        (uint256 amountExercised, uint256 amountUnexercised) = _getExercisedAmountsForClaim(optionKey, claimKey);

        // The sum of exercised and unexercised is the amount written.
        uint256 amountWritten = amountExercised + amountUnexercised;

        claimInfo = Claim({
            amountWritten: amountWritten,
            amountExercised: amountExercised,
            optionId: uint256(optionKey) << OPTION_ID_PADDING,
            // If the claim is initialized, it is unredeemed.
            unredeemed: true
        });
    }

    /// @inheritdoc IOptionSettlementEngine
    function underlying(uint256 tokenId) external view returns (Underlying memory underlyingPosition) {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(tokenId);

        // Check the type of token and if it exists.
        TokenType typeOfToken = tokenType(tokenId);

        if (typeOfToken == TokenType.None) {
            revert TokenNotFound(tokenId);
        }

        Option storage optionRecord = optionTypeStates[optionKey].option;

        if (typeOfToken == TokenType.Option) {
            // Then tokenId is an initialized option type.

            // If the option type is expired, then it has no underlying position.
            uint40 expiry = optionRecord.expiryTimestamp;
            if (expiry <= block.timestamp) {
                revert ExpiredOption(tokenId, expiry);
            }

            underlyingPosition = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: int256(uint256(optionRecord.underlyingAmount)),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: -int256(uint256(optionRecord.exerciseAmount))
            });
        } else {
            // Then tokenId is an initialized/unredeemed claim.
            (uint256 amountExercised, uint256 amountUnexercised) = _getExercisedAmountsForClaim(optionKey, claimKey);

            underlyingPosition = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: int256(amountUnexercised * optionRecord.underlyingAmount),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: int256(amountExercised * optionRecord.exerciseAmount)
            });
        }
    }

    /// @inheritdoc IOptionSettlementEngine
    function tokenType(uint256 tokenId) public view returns (TokenType typeOfToken) {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(tokenId);

        // Default to None if option or claim is uninitialized or redeemed.
        typeOfToken = TokenType.None;

        // Check if the token is an initialized option or claim and update accordingly.
        if (isOptionInitialized(optionKey)) {
            if ((tokenId & CLAIM_NUMBER_MASK) == 0) {
                typeOfToken = TokenType.Option;
            } else if (isClaimInitialized(optionKey, claimKey)) {
                typeOfToken = TokenType.Claim;
            }
        }
    }

    /**
     * @notice Returns the URI for a given token ID.
     */
    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        Option memory optionInfo = optionTypeStates[uint160(tokenId >> OPTION_ID_PADDING)].option;

        TokenType typeOfToken = tokenType(tokenId);

        if (typeOfToken == TokenType.None) {
            revert TokenNotFound(tokenId);
        }

        ITokenURIGenerator.TokenURIParams memory params = ITokenURIGenerator.TokenURIParams({
            underlyingAsset: optionInfo.underlyingAsset,
            underlyingSymbol: ERC20(optionInfo.underlyingAsset).symbol(),
            exerciseAsset: optionInfo.exerciseAsset,
            exerciseSymbol: ERC20(optionInfo.exerciseAsset).symbol(),
            exerciseTimestamp: optionInfo.exerciseTimestamp,
            expiryTimestamp: optionInfo.expiryTimestamp,
            underlyingAmount: optionInfo.underlyingAmount,
            exerciseAmount: optionInfo.exerciseAmount,
            tokenType: typeOfToken
        });

        return tokenURIGenerator.constructTokenURI(params);
    }

    /*//////////////////////////////////////////////////////////////
    //  Public/External Mutators
    //////////////////////////////////////////////////////////////*/

    //
    //  Write Options
    //

    /// @inheritdoc IOptionSettlementEngine
    function newOptionType(
        address underlyingAsset,
        uint96 underlyingAmount,
        address exerciseAsset,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) external returns (uint256 optionId) {
        // @dev This is how to precalculate the option key and id.
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
        optionId = uint256(optionKey) << OPTION_ID_PADDING;

        if (isOptionInitialized(optionKey)) {
            revert OptionsTypeExists(optionId);
        }

        if (expiryTimestamp < (block.timestamp + 1 days)) {
            revert ExpiryWindowTooShort(expiryTimestamp);
        }

        if (expiryTimestamp < (exerciseTimestamp + 1 days)) {
            revert ExerciseWindowTooShort(exerciseTimestamp);
        }

        // The exercise and underlying assets can't be the same.
        if (exerciseAsset == underlyingAsset) {
            revert InvalidAssets(exerciseAsset, underlyingAsset);
        }

        // Check that both tokens are ERC20 and will be redeemable by
        // instantiating them and checking supply.
        ERC20 underlyingToken = ERC20(underlyingAsset);
        ERC20 exerciseToken = ERC20(exerciseAsset);
        if (underlyingToken.totalSupply() < underlyingAmount || exerciseToken.totalSupply() < exerciseAmount) {
            revert InvalidAssets(underlyingAsset, exerciseAsset);
        }

        optionTypeStates[optionKey].option = Option({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp,
            settlementSeed: optionKey,
            nextClaimKey: 1
        });

        emit NewOptionType(
            optionId,
            exerciseAsset,
            underlyingAsset,
            exerciseAmount,
            underlyingAmount,
            exerciseTimestamp,
            expiryTimestamp
            );
    }

    /// @inheritdoc IOptionSettlementEngine
    function write(uint256 tokenId, uint112 amount) public returns (uint256) {
        // Amount written must be greater than zero.
        if (amount == 0) {
            revert AmountWrittenCannotBeZero();
        }

        // Get the optionKey and claimKey from the tokenId.
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(tokenId);

        // Sanitize a zeroed encodedOptionId from the optionKey.
        uint256 encodedOptionId = uint256(optionKey) << OPTION_ID_PADDING;

        // Get the option record and check that it's valid to write against
        OptionTypeState storage optionTypeState = optionTypeStates[optionKey];

        // by making sure the option exists, and hasn't expired.
        uint40 expiry = optionTypeState.option.expiryTimestamp;
        if (expiry == 0) {
            revert InvalidOption(encodedOptionId);
        }
        if (expiry <= block.timestamp) {
            revert ExpiredOption(encodedOptionId, expiry);
        }

        // Update internal bucket accounting.
        uint16 bucketIndex = _addOrUpdateClaimBucket(optionTypeState, amount);

        // Calculate the amount to transfer in.
        uint256 rxAmount = optionTypeState.option.underlyingAmount * amount;
        address underlyingAsset = optionTypeState.option.underlyingAsset;

        // Assess a fee (if fee switch enabled) and emit events.
        uint256 fee = 0;
        if (feesEnabled) {
            fee = _calculateRecordAndEmitFee(encodedOptionId, underlyingAsset, rxAmount);
        }

        if (claimKey == 0) {
            // Then create a new claim.

            // Make encodedClaimId reflect the next available claim, and increment the next
            // available claim in storage.
            uint96 nextClaimKey = optionTypeState.option.nextClaimKey++;
            tokenId = _encodeTokenId(optionKey, nextClaimKey);

            // Add claim bucket indices
            _addOrUpdateClaimIndex(optionTypeStates[optionKey], nextClaimKey, bucketIndex, amount);

            // Emit event about options written on a new claim.
            emit OptionsWritten(encodedOptionId, msg.sender, tokenId, amount);

            // Mint a new claim token and transfer option tokens.
            uint256[] memory tokens = new uint256[](2);
            tokens[0] = encodedOptionId;
            tokens[1] = tokenId;

            uint256[] memory amounts = new uint256[](2);
            amounts[0] = amount;
            amounts[1] = 1; // claim NFT

            _batchMint(msg.sender, tokens, amounts, "");
        } else {
            // Then add to an existing claim.

            // The user must own the existing claim.
            uint256 balance = balanceOf[msg.sender][tokenId];
            if (balance != 1) {
                revert CallerDoesNotOwnClaimId(tokenId);
            }

            // Add claim bucket indices
            _addOrUpdateClaimIndex(optionTypeStates[optionKey], claimKey, bucketIndex, amount);

            // Emit event about options written on existing claim.
            emit OptionsWritten(encodedOptionId, msg.sender, tokenId, amount);

            // Mint more options on existing claim to writer.
            _mint(msg.sender, encodedOptionId, amount, "");
        }

        // Transfer in the requisite underlying asset amount.
        SafeTransferLib.safeTransferFrom(ERC20(underlyingAsset), msg.sender, address(this), (rxAmount + fee));

        return tokenId;
    }

    //
    //  Redeem Claims
    //

    /// @inheritdoc IOptionSettlementEngine
    function redeem(uint256 claimId) external {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(claimId);

        // You can't redeem an option.
        if (claimKey == 0) {
            revert InvalidClaim(claimId);
        }

        // If the user has a claim, we already know the claim exists and is initialized.
        uint256 balance = balanceOf[msg.sender][claimId];
        if (balance != 1) {
            revert CallerDoesNotOwnClaimId(claimId);
        }

        // Setup pointers to the option and info.
        OptionTypeState storage optionTypeState = optionTypeStates[optionKey];
        Option memory optionRecord = optionTypeState.option;

        // Can't redeem until expiry.
        if (optionRecord.expiryTimestamp > block.timestamp) {
            revert ClaimTooSoon(claimId, optionRecord.expiryTimestamp);
        }

        // Set up accumulators.
        ClaimIndex[] storage claimIndices = optionTypeState.claimIndices[claimKey];
        uint256 claimIndexArrayLength = claimIndices.length;
        uint256 totalExerciseAssetAmount;
        uint256 totalUnderlyingAssetAmount;
        uint256 amountExercisedInBucket;
        uint256 amountUnexercisedInBucket;

        unchecked {
            for (uint256 i = claimIndexArrayLength; i > 0; i--) {
                (amountExercisedInBucket, amountUnexercisedInBucket) =
                    _getExercisedAmountsForClaimIndex(optionTypeState, claimIndices, i - 1);
                // Accumulate the amount exercised and unexercised in these variables
                // for later multiplication by optionRecord.exerciseAmount/underlyingAmount.
                totalExerciseAssetAmount += amountExercisedInBucket;
                totalUnderlyingAssetAmount += amountUnexercisedInBucket;
                // This zeroes out the array during the redemption process for a gas refund.
                claimIndices.pop();
            }
        }

        // Calculate the amounts to transfer out.
        totalExerciseAssetAmount *= optionRecord.exerciseAmount;
        totalUnderlyingAssetAmount *= optionRecord.underlyingAmount;

        emit ClaimRedeemed(
            claimId,
            uint256(optionKey) << OPTION_ID_PADDING,
            msg.sender,
            totalExerciseAssetAmount,
            totalUnderlyingAssetAmount
            );

        // Make transfers.
        _burn(msg.sender, claimId, 1);

        if (totalExerciseAssetAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.exerciseAsset), msg.sender, totalExerciseAssetAmount);
        }

        if (totalUnderlyingAssetAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, totalUnderlyingAssetAmount);
        }
    }

    //
    //  Exercise Options
    //

    /// @inheritdoc IOptionSettlementEngine
    function exercise(uint256 optionId, uint112 amount) external {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(optionId);

        // Must be an optionId.
        if (claimKey != 0) {
            revert InvalidOption(optionId);
        }

        Option storage optionRecord = optionTypeStates[optionKey].option;

        // These will implicitly check that the option type is initialized.

        // Can't exercise an option at or after expiry
        if (optionRecord.expiryTimestamp <= block.timestamp) {
            revert ExpiredOption(optionId, optionRecord.expiryTimestamp);
        }

        // Can't exercise an option before the exercise timestamp
        if (optionRecord.exerciseTimestamp > block.timestamp) {
            revert ExerciseTooEarly(optionId, optionRecord.exerciseTimestamp);
        }

        if (balanceOf[msg.sender][optionId] < amount) {
            revert CallerHoldsInsufficientOptions(optionId, amount);
        }

        // Calculate the amount to transfer in/out.
        uint256 rxAmount = optionRecord.exerciseAmount * amount;
        uint256 txAmount = optionRecord.underlyingAmount * amount;
        address exerciseAsset = optionRecord.exerciseAsset;
        address underlyingAsset = optionRecord.underlyingAsset;

        // Assign exercise to writers.
        _assignExercise(optionKey, optionRecord, amount);

        // Assess a fee (if fee switch enabled) and emit events.
        uint256 fee = 0;
        if (feesEnabled) {
            fee = _calculateRecordAndEmitFee(optionId, exerciseAsset, rxAmount);
        }
        emit OptionsExercised(optionId, msg.sender, amount);

        _burn(msg.sender, optionId, amount);

        // Transfer in the required amount of the exercise asset.
        SafeTransferLib.safeTransferFrom(ERC20(exerciseAsset), msg.sender, address(this), (rxAmount + fee));

        // Transfer out the required amount of the underlying asset.
        SafeTransferLib.safeTransfer(ERC20(underlyingAsset), msg.sender, txAmount);
    }

    //
    //  Protocol Admin
    //

    /// @inheritdoc IOptionSettlementEngine
    function setFeesEnabled(bool enabled) external onlyFeeTo {
        feesEnabled = enabled;

        emit FeeSwitchUpdated(feeTo, enabled);
    }

    /// @inheritdoc IOptionSettlementEngine
    function setFeeTo(address newFeeTo) external onlyFeeTo {
        if (newFeeTo == address(0)) {
            revert InvalidAddress(address(0));
        }
        feeTo = newFeeTo;

        emit FeeToUpdated(newFeeTo);
    }

    /// @inheritdoc IOptionSettlementEngine
    function sweepFees(address[] memory tokens) external {
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
                    emit FeeSwept(token, sendFeeTo, sweep);
                    SafeTransferLib.safeTransfer(ERC20(token), sendFeeTo, sweep);
                }
            }
        }
    }

    /// @inheritdoc IOptionSettlementEngine
    function setTokenURIGenerator(address newTokenURIGenerator) external onlyFeeTo {
        if (newTokenURIGenerator == address(0)) {
            revert InvalidAddress(address(0));
        }
        tokenURIGenerator = ITokenURIGenerator(newTokenURIGenerator);

        emit TokenURIGeneratorUpdated(newTokenURIGenerator);
    }

    /*//////////////////////////////////////////////////////////////
    //  Private Views
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode the supplied option id and claim id
     * @param optionKey The optionKey to encode.
     * @param claimKey The claimKey to encode.
     * @return tokenId The encoded token id.
     */
    function _encodeTokenId(uint160 optionKey, uint96 claimKey) private pure returns (uint256 tokenId) {
        tokenId |= uint256(optionKey) << OPTION_ID_PADDING;
        tokenId |= uint256(claimKey);
    }

    /**
     * @notice Decode the supplied token id
     * @dev See tokenType() for encoding scheme
     * @param tokenId The token id to decode
     * @return optionKey claimNum The decoded components of the id as described above, padded as required
     */
    function _decodeTokenId(uint256 tokenId) private pure returns (uint160 optionKey, uint96 claimKey) {
        // move key to lsb to fit into uint160
        optionKey = uint160(tokenId >> OPTION_ID_PADDING);

        // grab lower 96b of id for claim number
        claimKey = uint96(tokenId & CLAIM_NUMBER_MASK);
    }

    /**
     * @notice Checks to see if an option type is already initialized.
     * @param optionKey The option key to check.
     * @return initialized Whether or not the option type is initialized.
     */
    function isOptionInitialized(uint160 optionKey) private view returns (bool initialized) {
        return optionTypeStates[optionKey].option.underlyingAsset != address(0);
    }

    /**
     * @notice Checks to see if an claim is already initialized.
     * @param optionKey The option key to check.
     * @param claimKey The claim key to check.
     * @return initialized Whether or not the claim is initialized.
     */
    function isClaimInitialized(uint160 optionKey, uint96 claimKey) private view returns (bool initialized) {
        return optionTypeStates[optionKey].claimIndices[claimKey].length > 0;
    }

    /// @return settlementPeriods The number of settlement bucket periods after the epoch.
    function _getDaysBucket() private view returns (uint16 settlementPeriods) {
        return uint16(block.timestamp / 1 days);
    }

    function _getExercisedAmountsForClaimIndex(
        OptionTypeState storage optionTypeState,
        ClaimIndex[] storage claimIndexArray,
        uint256 index
    ) private view returns (uint256 amountExercised, uint256 amountUnexercised) {
        // TODO(Possible rounding error)
        ClaimIndex storage claimIndex = claimIndexArray[index];
        Bucket storage bucket = optionTypeState.bucketInfo.buckets[claimIndex.bucketIndex];
        // The ratio of exercised to written options in the bucket multiplied by the
        // number of options actually written in the claim.
        amountExercised =
            FixedPointMathLib.mulDivDown(bucket.amountExercised, claimIndex.amountWritten, bucket.amountWritten);

        // The ratio of unexercised to written options in the bucket multiplied by the
        // number of options actually written in the claim.
        amountUnexercised = FixedPointMathLib.mulDivDown(
            bucket.amountWritten - bucket.amountExercised, claimIndex.amountWritten, bucket.amountWritten
        );
    }

    /**
     * @notice Calculates, records, and emits an event for a fee accrual.
     */
    function _calculateRecordAndEmitFee(uint256 optionId, address assetAddress, uint256 assetAmount)
        private
        returns (uint256 fee)
    {
        fee = (assetAmount * feeBps) / 10_000;
        feeBalance[assetAddress] += fee;

        emit FeeAccrued(optionId, assetAddress, msg.sender, fee);
    }

    /// @dev Performs fair exercise assignment via the pseudorandom selection of a claim
    /// bucket between the initial creation of the option type and "today". The buckets
    /// are then iterated from oldest to newest (looping if we reach "today") if the
    /// exercise amount overflows into another bucket. The seed for the pseudorandom
    /// index is updated accordingly on the option type.
    function _assignExercise(uint160 optionKey, Option storage optionRecord, uint112 amount) private {
        // A bucket of the overall amounts written and exercised for all claims
        // on a given day
        Bucket[] storage claimBuckets = optionTypeStates[optionKey].bucketInfo.buckets;
        uint16[] storage unexercisedBucketIndices = optionTypeStates[optionKey].bucketInfo.bucketsWithCollateral;
        uint16 unexercisedBucketsMod = uint16(unexercisedBucketIndices.length);
        uint16 unexercisedBucketsIndex = uint16(optionRecord.settlementSeed % unexercisedBucketsMod);
        while (amount > 0) {
            // get the claim bucket to assign
            uint16 bucketIndex = unexercisedBucketIndices[unexercisedBucketsIndex];
            Bucket storage claimBucketInfo = claimBuckets[bucketIndex];

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

                optionTypeStates[optionKey].bucketInfo.bucketHasCollateral[bucketIndex] = false;
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

    /**
     * @notice Get the amount of options exercised and amount unexercised for a given claim.
     */
    function _getExercisedAmountsForClaim(uint160 optionKey, uint96 claimKey)
        private
        view
        returns (uint256 amountExercised, uint256 amountUnexercised)
    {
        // Set these to zero to start with
        amountExercised = 0;
        amountUnexercised = 0;

        OptionTypeState storage optionTypeState = optionTypeStates[optionKey];
        ClaimIndex[] storage claimIndexArray = optionTypeState.claimIndices[claimKey];
        uint256 len = claimIndexArray.length;
        uint256 amountExercisedInBucket;
        uint256 amountUnexercisedInBucket;

        unchecked {
            for (uint256 i = 0; i < len; i++) {
                (amountExercisedInBucket, amountUnexercisedInBucket) =
                    _getExercisedAmountsForClaimIndex(optionTypeState, claimIndexArray, i);
                amountExercised += amountExercisedInBucket;
                amountUnexercised += amountUnexercisedInBucket;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
    //  Internal Mutators
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds or updates a claim bucket as needed for a given option type
     * and amount of options written, based on the present time and bucket
     * state.
     */
    function _addOrUpdateClaimBucket(OptionTypeState storage optionTypeState, uint112 amount)
        private
        returns (uint16)
    {
        BucketInfo storage bucketInfo = optionTypeState.bucketInfo;
        Bucket[] storage claimBuckets = bucketInfo.buckets;
        uint16 daysAfterEpoch = _getDaysBucket();
        uint16 bucketIndex = uint16(claimBuckets.length);

        if (claimBuckets.length == 0) {
            // Then add a new claim bucket to this option type, because none exist.
            claimBuckets.push(Bucket(amount, 0, daysAfterEpoch));
            _updateUnexercisedBucketIndices(bucketInfo, bucketIndex);

            return bucketIndex;
        }

        // Else, get the currentBucket.
        Bucket storage currentBucket = claimBuckets[bucketIndex - 1];

        if (currentBucket.daysAfterEpoch < daysAfterEpoch) {
            // Then we are out of the time range for currentBucket, so we need to
            // create a new bucket
            claimBuckets.push(Bucket(amount, 0, daysAfterEpoch));
            _updateUnexercisedBucketIndices(bucketInfo, bucketIndex);
        } else {
            // Then we are still in the time range for currentBucket, and thus
            // need to update it's state.
            currentBucket.amountWritten += amount;
            bucketIndex -= 1;

            // This block is executed if a bucket has been previously fully exercised
            // and now more options are being written into it.
            if (!bucketInfo.bucketHasCollateral[bucketIndex]) {
                _updateUnexercisedBucketIndices(bucketInfo, bucketIndex);
            }
        }

        return bucketIndex;
    }

    /**
     * @notice Adds the bucket index to the list of buckets with collateral
     * and sets the mapping for that bucket having collateral to true.
     */
    function _updateUnexercisedBucketIndices(BucketInfo storage bucketInfo, uint16 bucketIndex) internal {
        bucketInfo.bucketsWithCollateral.push(bucketIndex);
        bucketInfo.bucketHasCollateral[bucketIndex] = true;
    }

    /**
     * @notice Updates claimIndices for a given claim key.
     */
    function _addOrUpdateClaimIndex(
        OptionTypeState storage optionTypeState,
        uint96 claimKey,
        uint16 bucketIndex,
        uint112 amount
    ) private {
        ClaimIndex[] storage claimIndices = optionTypeState.claimIndices[claimKey];
        uint256 arrayLength = claimIndices.length;

        // If the array is empty, create a new index and return.
        if (arrayLength == 0) {
            claimIndices.push(ClaimIndex({amountWritten: amount, bucketIndex: bucketIndex}));

            return;
        }

        ClaimIndex storage lastIndex = claimIndices[arrayLength - 1];

        // If we are writing to an index that doesn't yet exist, create it and return.
        if (lastIndex.bucketIndex < bucketIndex) {
            claimIndices.push(ClaimIndex({amountWritten: amount, bucketIndex: bucketIndex}));

            return;
        }

        // Else, we are writing to an index that already exists. Update the amount written.
        lastIndex.amountWritten += amount;
    }
}
