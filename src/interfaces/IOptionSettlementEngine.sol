// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

/// @title A settlement engine for options
/// @author 0xAlcibiades
/// @author Flip-Liquid
/// @author neodaoist
interface IOptionSettlementEngine {
    /*//////////////////////////////////////////////////////////////
    //  Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new unique options type is created.
     * @param optionId The id of the initial option created.
     * @param exerciseAsset The contract address of the exercise asset.
     * @param underlyingAsset The contract address of the underlying asset.
     * @param exerciseAmount The amount of the exercise asset to be exercised.
     * @param underlyingAmount The amount of the underlying asset in the option.
     * @param exerciseTimestamp The timestamp after which this option can be exercised.
     * @param expiryTimestamp The timestamp before which this option can be exercised.
     */
    event NewOptionType(
        uint256 optionId,
        address indexed exerciseAsset,
        address indexed underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount,
        uint40 exerciseTimestamp,
        uint40 indexed expiryTimestamp
    );

    /**
     * @notice Emitted when a new option is written.
     * @param optionId The id of the newly written option.
     * @param writer The address of the writer of the new option.
     * @param claimId The claim ID for the option.
     * @param amount The amount of options written.
     */
    event OptionsWritten(uint256 indexed optionId, address indexed writer, uint256 indexed claimId, uint112 amount);

    /**
     * @notice Emitted when a claim is redeemed.
     * @param optionId The id of the option the claim is being redeemed against.
     * @param claimId The id of the claim being redeemed.
     * @param redeemer The address redeeming the claim.
     * @param exerciseAsset The exercise asset of the option.
     * @param underlyingAsset The underlying asset of the option.
     * @param exerciseAmountRedeemed The amount of options being
     * @param underlyingAmountRedeemed The amount of underlying
     */
    event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        address exerciseAsset,
        address underlyingAsset,
        uint256 exerciseAmountRedeemed,
        uint256 underlyingAmountRedeemed
    );

    /**
     * @notice Emitted when an option is exercised.
     * @param optionId The id of the option being exercised.
     * @param exerciser The address exercising the option.
     * @param amount The amount of options being exercised.
     */
    event OptionsExercised(uint256 indexed optionId, address indexed exerciser, uint112 amount);

    /**
     * @notice Emitted when protocol fees are accrued for a given asset.
     * @dev Emitted on write() when fees are accrued on the underlying asset,
     * or exercise() when fees are accrued on the exercise asset.
     * @param optionId The id of the option being written or exercised.
     * @param asset Asset for which fees are accrued.
     * @param payer The address paying the fee.
     * @param amount The amount of fees which are accrued.
     */
    event FeeAccrued(uint256 indexed optionId, address indexed asset, address indexed payer, uint256 amount);

    /**
     * @notice Emitted when accrued protocol fees for a given token are swept to the
     * feeTo address.
     * @param asset The token for which protocol fees are being swept.
     * @param feeTo The account to which fees are being swept.
     * @param amount The total amount being swept.
     */
    event FeeSwept(address indexed asset, address indexed feeTo, uint256 amount);

    /**
     * @notice Emitted when fee switch is updated.
     * @param feeTo The address which altered the switch state.
     * @param enabled Whether the fee switch is enabled or disabled.
     */
    event FeeSwitchUpdated(address feeTo, bool enabled);

    /**
     * @notice Emitted when feeTo address is updated.
     * @param newFeeTo The new feeTo address.
     */
    event FeeToUpdated(address indexed newFeeTo);

    /*//////////////////////////////////////////////////////////////
    //  Errors
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The requested token is not found.
     * @param token token requested.
     */
    error TokenNotFound(uint256 token);

    /**
     * @notice The caller doesn't have permission to access that function.
     * @param accessor The requesting address.
     * @param permissioned The address which has the requisite permissions.
     */
    error AccessControlViolation(address accessor, address permissioned);

    /**
     * @notice Invalid fee to address.
     * @param feeTo The feeTo address.
     */
    error InvalidFeeToAddress(address feeTo);

    /**
     * @notice Invalid TokenURIGenerator address.
     * @param tokenURIGenerator The tokenURIGenerator address.
     */
    error InvalidTokenURIGeneratorAddress(address tokenURIGenerator);

    /**
     * @notice This options chain already exists and thus cannot be created.
     * @param optionId The id and hash of the options chain.
     */
    error OptionsTypeExists(uint256 optionId);

    /**
     * @notice The expiry timestamp is less than 24 hours from now.
     * @param expiry Timestamp of expiry
     */
    error ExpiryWindowTooShort(uint40 expiry);

    /**
     * @notice The option exercise window is less than 24 hours long.
     * @param exercise The timestamp supplied for exercise.
     */
    error ExerciseWindowTooShort(uint40 exercise);

    /**
     * @notice The assets specified are invalid or duplicate.
     * @param asset1 Supplied asset.
     * @param asset2 Supplied asset.
     */
    error InvalidAssets(address asset1, address asset2);

    /**
     * @notice The token specified is not an option.
     * @param token The supplied token.
     */
    error InvalidOption(uint256 token);

    /**
     * @notice The token specified is not a claim.
     * @param token The supplied token.
     */
    error InvalidClaim(uint256 token);

    /**
     * @notice The optionId specified expired at expiry.
     * @param optionId The id of the expired option.
     * @param expiry The time of expiry of the supplied option Id.
     */
    error ExpiredOption(uint256 optionId, uint40 expiry);

    /**
     * @notice This option cannot yet be exercised.
     * @param optionId Supplied option ID.
     * @param exercise The time when the optionId can be exercised.
     */
    error ExerciseTooEarly(uint256 optionId, uint40 exercise);

    /**
     * @notice This claim is not owned by the caller.
     * @param claimId Supplied claim ID.
     */
    error CallerDoesNotOwnClaimId(uint256 claimId);

    /**
     * @notice The caller does not have enough of the option to exercise the amount
     * specified.
     * @param optionId The supplied option id.
     * @param amount The amount of the supplied option requested for exercise.
     */
    error CallerHoldsInsufficientOptions(uint256 optionId, uint112 amount);

    /**
     * @notice You can't claim before expiry.
     * @param claimId Supplied claim ID.
     * @param expiry timestamp at which the options chain expires
     */
    error ClaimTooSoon(uint256 claimId, uint40 expiry);

    /// @notice The amount provided to write() must be > 0.
    error AmountWrittenCannotBeZero();

    /*//////////////////////////////////////////////////////////////
    //  Data structures
    //////////////////////////////////////////////////////////////*/

    /// @dev This enumeration is used to determine the type of an ERC1155 subtoken in the engine.
    enum Type {
        None,
        Option,
        Claim
    }

    /// @dev This struct contains the data about an options type associated with an ERC-1155 token.
    struct Option {
        /// @param underlyingAsset The underlying asset to be received
        address underlyingAsset;
        /// @param underlyingAmount The amount of the underlying asset contained within an option contract of this type
        uint96 underlyingAmount;
        /// @param exerciseAsset The address of the asset needed for exercise
        address exerciseAsset;
        /// @param exerciseAmount The amount of the exercise asset required to exercise this option
        uint96 exerciseAmount;
        /// @param exerciseTimestamp The timestamp after which this option can be exercised
        uint40 exerciseTimestamp;
        /// @param expiryTimestamp The timestamp before which this option can be exercised
        uint40 expiryTimestamp;
        /// @param settlementSeed Random seed created at the time of option type creation
        uint160 settlementSeed;
        /// @param nextClaimNum Which option was written
        uint96 nextClaimNum;
    }

    struct BucketInfo {
        /// @notice Buckets of claims grouped by period
        /// @dev This is to enable O(constant) time options exercise. When options are written,
        /// the Claim struct in this mapping is updated to reflect the cumulative amount written
        /// on the day in question. write() will add unexercised options into the bucket
        /// corresponding to the # of days after the option type's creation.
        /// exercise() will randomly assign exercise to a bucket <= the current day.
        Bucket[] buckets;
        /// @notice An array of unexercised bucket indices.
        uint16[] unexercisedBuckets;
        /// @notice Maps a bucket's index (in _claimBucketByOption) to a boolean indicating
        /// if the bucket has any unexercised options.
        /// @dev Used to determine if a bucket index needs to be added to
        /// unexercisedBuckets during write(). Set false if a bucket is fully
        /// exercised.
        mapping(uint16 => bool) doesBucketHaveUnexercisedOptions;
    }

    struct OptionEngineState {
        /// @notice Information about the option type
        Option option;
        /// @notice Information about the option's claim buckets
        BucketInfo bucketInfo;
        /// @notice Information about the option's claims
        mapping(uint96 => ClaimIndex[]) claimIndices;
    }

    /**
     * @dev This struct contains the data about a lot of options written for a particular option type.
     * When writing an amount of options of a particular type, the writer will be issued an ERC 1155 NFT
     * that represents a claim to the underlying and exercise assets of the options lot, to be claimed after
     * expiry of the option. The amount of each (underlying asset and exercise asset) paid to the claimant upon
     * redeeming their claim NFT depends on the option type, the amount of options written in their options lot
     * (represented in this struct) and what portion of their lot was exercised before expiry.
     */
    struct Claim {
        /// @param amountWritten The number of options written in this option lot claim
        uint112 amountWritten;
        /// @param amountExercised The amount of options that have been exercised in this lot
        uint112 amountExercised;
        /// @param optionId The option ID corresponding to the option type for which this lot is
        /// written.
        uint256 optionId;
        /// @param unredeemed Whether or not this option lot has been claimed by the writer
        bool unredeemed;
    }

    /**
     * @dev Options lots are able to have options added to them on after the initial
     * writing. This struct is used to keep track of how many options in a single lot
     * are written on each day, in order to correctly perform fair assignment.
     */
    struct ClaimIndex {
        /// @param amountWritten The amount of options written on a given day/bucket
        uint112 amountWritten;
        /// @param bucketIndex The index of the OptionsDayBucket in which the options are written
        uint16 bucketIndex;
    }

    /**
     * @dev Represents the total amount of options written and exercised for a group of
     * claims bucketed by day. Used in fair assignement to calculate the ratio of
     * underlying to exercise assets to be transferred to claimants.
     */
    struct Bucket {
        /// @param amountWritten The number of options written in this bucket
        uint112 amountWritten;
        /// @param amountExercised The number of options exercised in this bucket
        uint112 amountExercised;
        /// @param daysAfterEpoch Which day this bucket falls on, in offset from epoch
        uint16 daysAfterEpoch;
    }

    /**
     * @dev Struct used in returning data regarding positions underlying a claim or option.
     */
    struct Underlying {
        /// @param underlyingAsset address of the underlying asset erc20
        address underlyingAsset;
        /// @param underlyingPosition position on the underlying asset
        int256 underlyingPosition;
        /// @param exerciseAsset address of the exercise asset erc20
        address exerciseAsset;
        /// @param exercisePosition position on the exercise asset
        int256 exercisePosition;
    }

    /*//////////////////////////////////////////////////////////////
    //  Accessors
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns Option struct details about a given tokenID if that token is
     * an option.
     * @param tokenId The id of the option.
     * @return option The Option struct for tokenId.
     */
    function option(uint256 tokenId) external view returns (Option memory option);

    /**
     * @notice Returns information about the exercised and unexercised assets associated with
     * an options lot claim.
     * @param claimId The id of the claim
     * @return claim The Claim struct reflecting information about the claim.
     */
    function claim(uint256 claimId) external view returns (Claim memory claim);

    /**
     * @notice Information about the position underlying a token, useful for determining value.
     * When supplied an Option Lot Claim id, this function returns the total amounts of underlying
     * and exercise assets currently associated with a given options lot.
     * @param tokenId The token id for which to retrieve the Underlying position.
     * @return underlyingPositions The Underlying struct for the supplied tokenId.
     */
    function underlying(uint256 tokenId) external view returns (Underlying memory underlyingPositions);

    /**
     * @notice Returns the token type (e.g. Option/Claim) for a given token Id
     * @param tokenId The id of the option or claim.
     * @return The enum (uint8) Type of the tokenId
     */
    function tokenType(uint256 tokenId) external view returns (Type);

    /**
     * @notice Check to see if an option is already initialized
     * @param optionKey The option key to check
     * @return Whether or not the option is initialized
     */
    function isOptionInitialized(uint160 optionKey) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
    //  Token ID Encoding
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encode the supplied option id and claim id
     * @dev Option and claim token ids are encoded as follows:
     *
     *   MSb
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┐
     *   0000 0000   0000 0000   0000 0000   0000 0000 │
     *   0000 0000   0000 0000   0000 0000   0000 0000 │ 160b option key, created from hash of Option struct
     *   0000 0000   0000 0000   0000 0000   0000 0000 │
     *   0000 0000   0000 0000   0000 0000   0000 0000 │
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┘
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┐
     *   0000 0000   0000 0000   0000 0000   0000 0000 │ 96b auto-incrementing option lot claim number
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┘
     *                                             LSb
     * @param optionKey The optionKey to encode
     * @param claimNum The claimNum to encode
     * @return tokenId The encoded token id
     */
    function encodeTokenId(uint160 optionKey, uint96 claimNum) external pure returns (uint256 tokenId);

    /**
     * @notice Decode the supplied token id
     * @dev See encodeTokenId() for encoding scheme
     * @param tokenId The token id to decode
     * @return optionKey claimNum The decoded components of the id as described above, padded as required
     */
    function decodeTokenId(uint256 tokenId) external pure returns (uint160 optionKey, uint96 claimNum);

    /*//////////////////////////////////////////////////////////////
    //  Write Options
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new option type if it doesn't already exist
     * @param underlyingAsset The contract address of the underlying asset.
     * @param underlyingAmount The amount of the underlying asset in the option.
     * @param exerciseAsset The contract address of the exercise asset.
     * @param exerciseAmount The amount of the exercise asset to be exercised.
     * @param exerciseTimestamp The timestamp after which this option can be exercised.
     * @param expiryTimestamp The timestamp before which this option can be exercised.
     * @return optionId The optionId for the option.
     */
    function newOptionType(
        address underlyingAsset,
        uint96 underlyingAmount,
        address exerciseAsset,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) external returns (uint256 optionId);

    /**
     * @notice Writes a specified amount of the specified option, returning claim NFT id.
     * @param tokenId The desired token id to write against, set lower 96 bytes to zero to mint a new claim NFT
     * @param amount The desired number of options to write.
     */
    function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId);

    /*//////////////////////////////////////////////////////////////
    //  Exercise Options
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Exercises specified amount of optionId, transferring in the exercise asset,
     * and transferring out the underlying asset if requirements are met. Will revert with
     * an underflow/overflow if the user does not have the required assets.
     * @param optionId The option id to exercise.
     * @param amount The amount of option id to exercise.
     */
    function exercise(uint256 optionId, uint112 amount) external;

    /*//////////////////////////////////////////////////////////////
    //  Redeem Claims
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeem a claim NFT, transfers the underlying tokens.
     * @param claimId The ID of the claim to redeem.
     */
    function redeem(uint256 claimId) external;

    /*//////////////////////////////////////////////////////////////
    //  Protocol Admin
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if the protocol fee switch is enabled.
     * @return enabled Whether or not the protocol fee switch is enabled.
     */
    function feesEnabled() external view returns (bool enabled);

    /**
     * @notice Enable or disable protocol fees switch.
     * @param enabled Whether or not the protocol fee switch should be enabled.
     */
    function protocolFees(bool enabled) external;

    /**
     * @return fee The protocol fee, expressed in basis points.
     */
    function feeBps() external view returns (uint8 fee);

    /**
     * @notice The balance of protocol fees for a given token which have not yet
     * been swept.
     * @param token The token for the un-swept fee balance.
     * @return The balance of un-swept fees.
     */
    function feeBalance(address token) external view returns (uint256);

    /**
     * @notice Returns the address to which protocol fees are swept.
     * @return The address to which fees are swept.
     */
    function feeTo() external view returns (address);

    /**
     * @notice Updates the address fees can be swept to.
     * @param newFeeTo The new address to which fees can be swept.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Sweeps fees to the feeTo address if there is more than 1 wei for
     * feeBalance for a given token.
     * @param tokens The tokens for which fees will be swept to the feeTo address.
     */
    function sweepFees(address[] memory tokens) external;

    /**
     * @notice Updates the contract address for generating token URIs for Valorem positions.
     * @param newTokenURIGenerator The address of the new ITokenURIGenerator contract.
     */
    function setTokenURIGenerator(address newTokenURIGenerator) external;
}
