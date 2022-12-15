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

/*//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                //
//   $$$$$$$$$$                                                                                   //
//    $$$$$$$$                                  _|                                                //
//     $$$$$$ $$$$$$$$$$   _|      _|   _|_|_|  _|    _|_|    _|  _|_|   _|_|    _|_|_|  _|_|     //
//       $$    $$$$$$$$    _|      _| _|    _|  _|  _|    _|  _|_|     _|_|_|_|  _|    _|    _|   //
//   $$$$$$$$$$ $$$$$$       _|  _|   _|    _|  _|  _|    _|  _|       _|        _|    _|    _|   //
//    $$$$$$$$    $$           _|       _|_|_|  _|    _|_|    _|         _|_|_|  _|    _|    _|   //
//     $$$$$$                                                                                     //
//       $$                                                                                       //
//                                                                                                //
//////////////////////////////////////////////////////////////////////////////////////////////////*/

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
    // Internal Data Structures
    //////////////////////////////////////////////////////////////*/

    /// @notice Store the exercise state of a given collateral bucket
    enum BucketExerciseState {
        Exercised,
        PartiallyExercised,
        Unexercised
    }

    /**
     * @notice Claims can be used to write multiple times. This struct is used to keep track
     * of how many options are written against a claim in each bucket, in order to
     * correctly perform fair exercise assignment.
     */
    struct ClaimIndex {
        /// @custom:member amountWritten The amount of option contracts written into claim for given bucket.
        uint112 amountWritten;
        /// @custom:member bucketIndex The index of the Bucket into which the options collateral was deposited.
        uint96 bucketIndex;
    }

    /**
     * @notice Represents the total amount of options written and exercised for a group of
     * claims bucketed. Used in fair assignment to calculate the ratio of
     * underlying to exercise assets to be transferred to claimants.
     */
    struct Bucket {
        /// @custom:member amountWritten The number of option contracts written into this bucket.
        uint112 amountWritten;
        /// @custom:member amountExercised The number of option contracts exercised from this bucket.
        uint112 amountExercised;
    }

    /// @notice The claim bucket information for a given option type.
    struct BucketInfo {
        /// @custom:member An array of buckets for a given option type.
        Bucket[] buckets;
        /// @custom:member An array of bucket indices with collateral available for exercise.
        uint96[] unexercisedBucketIndices;
        /// @custom:member A mapping of bucket indices to a boolean indicating if the bucket has any collateral available for exercise.
        mapping(uint96 => BucketExerciseState) bucketExerciseStates;
    }

    /// @notice A storage container for the engine state of a given option type.
    struct OptionTypeState {
        /// @custom:member State for this option type.
        Option option;
        /// @custom:member State for assignment buckets on this option type.
        BucketInfo bucketInfo;
        /// @custom:member A mapping to an array of bucket indices per claim token for this option type.
        mapping(uint96 => ClaimIndex[]) claimIndices;
    }

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

        if (!_isOptionInitialized(optionKey)) {
            revert TokenNotFound(tokenId);
        }

        optionInfo = optionTypeStates[optionKey].option;
    }

    /// @inheritdoc IOptionSettlementEngine
    function claim(uint256 claimId) public view returns (Claim memory claimInfo) {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(claimId);

        if (!_isClaimInitialized(optionKey, claimKey)) {
            revert TokenNotFound(claimId);
        }

        // The sum of exercised and unexercised is the amount written.
        uint256 amountWritten;
        uint256 amountExercised;

        OptionTypeState storage optionTypeState = optionTypeStates[optionKey];
        ClaimIndex[] storage claimIndexArray = optionTypeState.claimIndices[claimKey];
        uint256 len = claimIndexArray.length;

        for (uint256 i = 0; i < len; i++) {
            ClaimIndex storage claimIndex = claimIndexArray[i];
            Bucket storage bucket = optionTypeState.bucketInfo.buckets[claimIndex.bucketIndex];
            amountWritten += claimIndex.amountWritten;
            amountExercised +=
                FixedPointMathLib.divWadDown((bucket.amountExercised * claimIndex.amountWritten), bucket.amountWritten);
        }

        claimInfo = Claim({
            // scale the amount written by WAD for consistency
            amountWritten: amountWritten * 1e18,
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
            uint256 totalUnderlyingAmount = 0;
            uint256 totalExerciseAmount = 0;

            OptionTypeState storage optionTypeState = optionTypeStates[optionKey];
            ClaimIndex[] storage claimIndices = optionTypeState.claimIndices[claimKey];
            uint256 len = claimIndices.length;
            uint256 underlyingAssetAmount = optionTypeState.option.underlyingAmount;
            uint256 exerciseAssetAmount = optionTypeState.option.exerciseAmount;

            for (uint256 i = 0; i < len; i++) {
                (uint256 indexUnderlyingAmount, uint256 indexExerciseAmount) = _getAssetAmountsForClaimIndex(
                    underlyingAssetAmount, exerciseAssetAmount, optionTypeState, claimIndices, i
                );
                totalUnderlyingAmount += indexUnderlyingAmount;
                totalExerciseAmount += indexExerciseAmount;
            }

            underlyingPosition = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: int256(totalUnderlyingAmount),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: int256(totalExerciseAmount)
            });
        }
    }

    /// @inheritdoc IOptionSettlementEngine
    function tokenType(uint256 tokenId) public view returns (TokenType typeOfToken) {
        (uint160 optionKey, uint96 claimKey) = _decodeTokenId(tokenId);

        // Default to None if option or claim is uninitialized or redeemed.
        typeOfToken = TokenType.None;

        // Check if the token is an initialized option or claim and update accordingly.
        if (_isOptionInitialized(optionKey)) {
            if ((tokenId & CLAIM_NUMBER_MASK) == 0) {
                typeOfToken = TokenType.Option;
            } else if (_isClaimInitialized(optionKey, claimKey)) {
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

        if (_isOptionInitialized(optionKey)) {
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
        uint96 bucketIndex = _addOrUpdateClaimBucket(optionTypeState, amount);

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

            // Add claim bucket indices.
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
        uint256 len = claimIndices.length;
        uint256 underlyingAssetAmount = optionTypeState.option.underlyingAmount;
        uint256 exerciseAssetAmount = optionTypeState.option.exerciseAmount;
        uint256 totalUnderlyingAssetAmount;
        uint256 totalExerciseAssetAmount;

        for (uint256 i = len; i > 0; i--) {
            (uint256 indexUnderlyingAmount, uint256 indexExerciseAmount) = _getAssetAmountsForClaimIndex(
                underlyingAssetAmount, exerciseAssetAmount, optionTypeState, claimIndices, i - 1
            );
            // Accumulate the amount exercised and unexercised in these variables
            // for later multiplication by optionRecord.exerciseAmount/underlyingAmount.
            totalUnderlyingAssetAmount += indexUnderlyingAmount;
            totalExerciseAssetAmount += indexExerciseAmount;
            // This zeroes out the array during the redemption process for a gas refund.
            claimIndices.pop();
        }

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

        OptionTypeState storage optionTypeState = optionTypeStates[optionKey];
        Option storage optionRecord = optionTypeState.option;

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
        _assignExercise(optionTypeState, optionRecord, amount);

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
    function _isOptionInitialized(uint160 optionKey) private view returns (bool initialized) {
        return optionTypeStates[optionKey].option.underlyingAsset != address(0);
    }

    /**
     * @notice Checks to see if an claim is already initialized.
     * @param optionKey The option key to check.
     * @param claimKey The claim key to check.
     * @return initialized Whether or not the claim is initialized.
     */
    function _isClaimInitialized(uint160 optionKey, uint96 claimKey) private view returns (bool initialized) {
        return optionTypeStates[optionKey].claimIndices[claimKey].length > 0;
    }

    /**
     * @notice Returns the exercised and unexercised amounts for a given claim index.
     */
    function _getAssetAmountsForClaimIndex(
        uint256 underlyingAssetAmount,
        uint256 exerciseAssetAmount,
        OptionTypeState storage optionTypeState,
        ClaimIndex[] storage claimIndexArray,
        uint256 index
    ) private view returns (uint256 underlyingAmount, uint256 exerciseAmount) {
        ClaimIndex storage claimIndex = claimIndexArray[index];
        Bucket storage bucket = optionTypeState.bucketInfo.buckets[claimIndex.bucketIndex];
        underlyingAmount += FixedPointMathLib.mulDivDown(
            (bucket.amountWritten - bucket.amountExercised) * underlyingAssetAmount,
            claimIndex.amountWritten,
            bucket.amountWritten
        );
        exerciseAmount += FixedPointMathLib.mulDivDown(
            bucket.amountExercised * exerciseAssetAmount, claimIndex.amountWritten, bucket.amountWritten
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

    /**
     * @notice Performs fair exercise assignment via the pseudorandom selection of a claim
     * bucket between the initial creation of the option type and "today". The buckets
     * are then iterated from oldest to newest (looping if we reach "today") if the
     * exercise amount overflows into another bucket. The seed for the pseudorandom
     * index is updated accordingly on the option type.
     */
    function _assignExercise(OptionTypeState storage optionTypeState, Option storage optionRecord, uint112 amount)
        private
    {
        // Setup pointers to buckets and buckets with collateral available for exercise.
        Bucket[] storage buckets = optionTypeState.bucketInfo.buckets;
        uint96[] storage unexercisedBucketIndices = optionTypeState.bucketInfo.unexercisedBucketIndices;
        uint96 numUnexercisedBuckets = uint96(unexercisedBucketIndices.length);
        uint96 exerciseIndex = uint96(optionRecord.settlementSeed % numUnexercisedBuckets);

        while (amount > 0) {
            // Get the claim bucket to assign exercise to.
            uint96 bucketIndex = unexercisedBucketIndices[exerciseIndex];
            Bucket storage bucketInfo = buckets[bucketIndex];

            uint112 amountAvailable = bucketInfo.amountWritten - bucketInfo.amountExercised;
            uint112 amountPresentlyExercised = 0;
            if (amountAvailable <= amount) {
                amount -= amountAvailable;
                amountPresentlyExercised = amountAvailable;
                // Perform "swap and pop" index management.
                numUnexercisedBuckets--;
                uint96 overwrite = unexercisedBucketIndices[numUnexercisedBuckets];
                unexercisedBucketIndices[exerciseIndex] = overwrite;
                unexercisedBucketIndices.pop();

                optionTypeState.bucketInfo.bucketExerciseStates[bucketIndex] = BucketExerciseState.Exercised;
            } else {
                amountPresentlyExercised = amount;
                amount = 0;
                optionTypeState.bucketInfo.bucketExerciseStates[bucketIndex] = BucketExerciseState.PartiallyExercised;
            }
            bucketInfo.amountExercised += amountPresentlyExercised;

            if (amount != 0) {
                exerciseIndex = (exerciseIndex + 1) % numUnexercisedBuckets;
            }
        }

        // Update the seed for the next exercise.
        optionRecord.settlementSeed =
            uint160(uint256(keccak256(abi.encode(optionRecord.settlementSeed, exerciseIndex))));
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
        returns (uint96 bucketIndex)
    {
        BucketInfo storage bucketInfo = optionTypeState.bucketInfo;
        Bucket[] storage claimBuckets = bucketInfo.buckets;
        uint96 writtenBucketIndex = uint96(claimBuckets.length);

        if (claimBuckets.length == 0) {
            // Then add a new bucket to this option type, because none exist.
            claimBuckets.push(Bucket(amount, 0));
            _updateUnexercisedBucketIndices(bucketInfo, writtenBucketIndex);

            return writtenBucketIndex;
        }

        // Else, get the currentBucket.
        uint96 currentBucketIndex = writtenBucketIndex - 1;
        Bucket storage currentBucket = claimBuckets[currentBucketIndex];

        if (bucketInfo.bucketExerciseStates[currentBucketIndex] != BucketExerciseState.Unexercised) {
            // Add a new bucket to this option type, because the last was exercised.
            claimBuckets.push(Bucket(amount, 0));
            _updateUnexercisedBucketIndices(bucketInfo, writtenBucketIndex);
        } else {
            // Write to the existing unexercised bucket
            currentBucket.amountWritten += amount;
            writtenBucketIndex = currentBucketIndex;
        }

        return writtenBucketIndex;
    }

    /**
     * @notice Adds the bucket index to the list of buckets with collateral
     * and sets the mapping for that bucket having collateral to true.
     */
    function _updateUnexercisedBucketIndices(BucketInfo storage bucketInfo, uint96 bucketIndex) internal {
        bucketInfo.unexercisedBucketIndices.push(bucketIndex);
        bucketInfo.bucketExerciseStates[bucketIndex] = BucketExerciseState.Unexercised;
    }

    /**
     * @notice Updates claimIndices for a given claim key.
     */
    function _addOrUpdateClaimIndex(
        OptionTypeState storage optionTypeState,
        uint96 claimKey,
        uint96 bucketIndex,
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
