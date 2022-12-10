// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./ITokenURIGenerator.sol";

interface IOptionSettlementEngine {
    /*//////////////////////////////////////////////////////////////
    //  Events
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new option type is created.
     * @param optionId The token id of the new option type created.
     * @param exerciseAsset The ERC20 contract address of the exercise asset.
     * @param underlyingAsset The ERC20 contract address of the underlying asset.
     * @param exerciseAmount The amount, in wei, of the exercise asset required to exercise each contract.
     * @param underlyingAmount The amount, in wei of the underlying asset in each contract.
     * @param exerciseTimestamp The timestamp after which this option type can be exercised.
     * @param expiryTimestamp The timestamp before which this option type can be exercised.
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
     * @notice Emitted when new options contracts are written.
     * @param optionId The token id of the option type written.
     * @param writer The address of the writer.
     * @param claimId The claim token id of the new or existing short position written against.
     * @param amount The amount of options contracts written.
     */
    event OptionsWritten(uint256 indexed optionId, address indexed writer, uint256 indexed claimId, uint112 amount);

    // TODO(Do we need exercise and underlying asset here?)
    /**
     * @notice Emitted when a claim is redeemed.
     * @param optionId The token id of the option type of the claim being redeemed.
     * @param claimId The token id of the claim being redeemed.
     * @param redeemer The address redeeming the claim.
     * @param exerciseAsset The ERC20 exercise asset of the option.
     * @param underlyingAsset The ERC20 underlying asset of the option.
     * @param exerciseAmountRedeemed The amount of the exerciseAsset redeemed.
     * @param underlyingAmountRedeemed The amount of underlyingAsset redeemed.
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
     * @notice Emitted when option contract(s) is(are) exercised.
     * @param optionId The token id of the option type exercised.
     * @param exerciser The address that exercised the option contract(s).
     * @param amount The amount of option contracts exercised.
     */
    event OptionsExercised(uint256 indexed optionId, address indexed exerciser, uint112 amount);

    /**
     * @notice Emitted when protocol fees are accrued for a given asset.
     * @dev Emitted on write() when fees are accrued on the underlying asset,
     * or exercise() when fees are accrued on the exercise asset.
     * Will not be emitted when feesEnabled is false.
     * @param optionId The token id of the option type being written or exercised.
     * @param asset The ERC20 asset in which fees were accrued.
     * @param payer The address paying the fee.
     * @param amount The amount, in wei, of fees accrued.
     */
    event FeeAccrued(uint256 indexed optionId, address indexed asset, address indexed payer, uint256 amount);

    /**
     * @notice Emitted when accrued protocol fees for a given ERC20 asset are swept to the
     * feeTo address.
     * @param asset The ERC20 asset of the protocol fees swept.
     * @param feeTo The account to which fees were swept.
     * @param amount The total amount swept.
     */
    event FeeSwept(address indexed asset, address indexed feeTo, uint256 amount);

    /**
     * @notice Emitted when protocol fees are enabled or disabled.
     * @param feeTo The address which enabled or disabled fees.
     * @param enabled Whether fees are enabled or disabled.
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
     * @param token The token requested.
     */
    error TokenNotFound(uint256 token);

    /**
     * @notice The caller doesn't have permission to access that function.
     * @param accessor The requesting address.
     * @param permissioned The address which has the requisite permissions.
     */
    error AccessControlViolation(address accessor, address permissioned);

    /**
     * @notice Invalid (zero) address.
     * @param input The address input.
     */
    error InvalidAddress(address input);

    /**
     * @notice This option contract type already exists and thus cannot be created.
     * @param optionId The token id of the option type which already exists.
     */
    error OptionsTypeExists(uint256 optionId);

    /**
     * @notice The expiry timestamp is too soon.
     * @param expiry Timestamp of expiry.
     */
    error ExpiryWindowTooShort(uint40 expiry);

    /**
     * @notice The option exercise window is too short.
     * @param exercise The timestamp supplied for exercise.
     */
    error ExerciseWindowTooShort(uint40 exercise);

    /**
     * @notice The assets specified are invalid or duplicate.
     * @param asset1 Supplied ERC20 asset.
     * @param asset2 Supplied ERC20 asset.
     */
    error InvalidAssets(address asset1, address asset2);

    /**
     * @notice The token specified is not an option token.
     * @param token The supplied token id.
     */
    error InvalidOption(uint256 token);

    /**
     * @notice The token specified is not a claim token.
     * @param token The supplied token id.
     */
    error InvalidClaim(uint256 token);

    /**
     * @notice The optionId specified expired has already expired.
     * @param optionId The id of the expired option.
     * @param expiry The expiry time for the supplied option Id.
     */
    error ExpiredOption(uint256 optionId, uint40 expiry);

    /**
     * @notice This option cannot yet be exercised.
     * @param optionId Supplied option ID.
     * @param exercise The time after which the option optionId be exercised.
     */
    error ExerciseTooEarly(uint256 optionId, uint40 exercise);

    /**
     * @notice This claim is not owned by the caller.
     * @param claimId Supplied claim ID.
     */
    error CallerDoesNotOwnClaimId(uint256 claimId);

    /**
     * @notice The caller does not have enough options contracts to exercise the amount
     * specified.
     * @param optionId The supplied option id.
     * @param amount The amount of options contracts which the caller attempted to exercise.
     */
    error CallerHoldsInsufficientOptions(uint256 optionId, uint112 amount);

    /**
     * @notice Claims cannot be redeemed before expiry.
     * @param claimId Supplied claim ID.
     * @param expiry timestamp at which the option type expires.
     */
    error ClaimTooSoon(uint256 claimId, uint40 expiry);

    /// @notice The amount of options contracts written must be greater than zero.
    error AmountWrittenCannotBeZero();

    /*//////////////////////////////////////////////////////////////
    //  Data structures
    //////////////////////////////////////////////////////////////*/

    /// @dev This enumeration is used to determine the type of an ERC1155 subtoken in the engine.
    enum Type {
        Option,
        Claim
    }

    /// @notice Data comprising the unique tuple of an option type associated with an ERC-1155 option token.
    struct Option {
        /// @custom:member underlyingAsset The underlying ERC20 asset which the option is collateralized with.
        address underlyingAsset;
        /// @custom:member underlyingAmount The amount of the underlying asset contained within an option contract of this type.
        uint96 underlyingAmount;
        /// @custom:member exerciseAsset The ERC20 asset which the option can be exercised using.
        address exerciseAsset;
        /// @custom:member exerciseAmount The amount of the exercise asset required to exercise each option contract of this type.
        uint96 exerciseAmount;
        /// @custom:member exerciseTimestamp The timestamp after which this option can be exercised.
        uint40 exerciseTimestamp;
        /// @custom:member expiryTimestamp The timestamp before which this option can be exercised.
        uint40 expiryTimestamp;
        /// @custom:member settlementSeed Deterministic seed used for option fair exercise assignment.
        uint160 settlementSeed;
        /// @custom:member nextClaimKey The next claim key available for this option type.
        uint96 nextClaimKey;
    }

    /// @notice The claim bucket information for a given option type.
    struct BucketInfo {
        /// @custom:member An array of buckets for a given option type.
        Bucket[] buckets;
        /// @custom:member An array of bucket indices with collateral available for exercise.
        uint16[] bucketsWithCollateral;
        /// @custom:member A mapping of bucket indices to a boolean indicating if the bucket has any collateral available for exercise.
        mapping(uint16 => bool) bucketHasCollateral;
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

    /**
     * @notice This struct contains the data about a claim to a short position written on an option type.
     * When writing an amount of options of a particular type, the writer will be issued an ERC 1155 NFT
     * that represents a claim to the underlying and exercise assets, to be claimed after
     * expiry of the option. The amount of each (underlying asset and exercise asset) paid to the claimant upon
     * redeeming their claim NFT depends on the option type, the amount of options written, represented in this struct,
     * and what portion of this claim was assigned exercise, if any, before expiry.
     */
    struct Claim {
        /// @custom:member amountWritten The number of option contracts written against this claim.
        uint112 amountWritten;
        /// @custom:member amountExercised The amount of option contracts exercised against this claim.
        uint112 amountExercised;
        /// @custom:member optionId The option ID of the option type this claim is for.
        uint256 optionId;
        /// @custom:member unredeemed Whether or not this claim has been redeemed.
        bool unredeemed;
    }

    /**
     * @notice Claims can be used to write multiple times. This struct is used to keep track
     * of how many options are written against a claim in each period, in order to
     * correctly perform fair exercise assignment.
     */
    struct ClaimIndex {
        /// @custom:member amountWritten The amount of option contracts written into claim for given period/bucket.
        uint112 amountWritten;
        /// @custom:member bucketIndex The index of the Bucket into which the options collateral was deposited.
        uint16 bucketIndex;
    }

    /**
     * @notice Represents the total amount of options written and exercised for a group of
     * claims bucketed by period. Used in fair assignment to calculate the ratio of
     * underlying to exercise assets to be transferred to claimants.
     */
    struct Bucket {
        /// @custom:member amountWritten The number of option contracts written into this bucket.
        uint112 amountWritten;
        /// @custom:member amountExercised The number of option contracts exercised from this bucket.
        uint112 amountExercised;
        /// @custom:member daysAfterEpoch Which period this bucket falls on, in offset from epoch.
        uint16 daysAfterEpoch;
    }

    /**
     * @notice Data about the ERC20 assets and liabilities for a given option (long) or claim (short) token,
     * in terms of the underlying and exercise ERC20 tokens.
     */
    struct Underlying {
        /// @param underlyingAsset The address of the ERC20 underlying asset.
        address underlyingAsset;
        /// @param underlyingPosition The amount, in wei, of the underlying asset represented by this position.
        int256 underlyingPosition;
        /// @param exerciseAsset The address of the ERC20 exercise asset.
        address exerciseAsset;
        /// @param exercisePosition The amount, in wei, of the exercise asset represented by this position.
        int256 exercisePosition;
    }

    /*//////////////////////////////////////////////////////////////
    //  Accessors
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get option type information for a given optionId.
     * @param optionId The id of the option.
     * @return option The Option struct for optionId if the tokenId is Type.Option.
     */
    function option(uint256 optionId) external view returns (Option memory option);

    /**
     * @notice Get information for a given claim token id.
     * @param claimId The id of the claim
     * @return claim The Claim struct for claimId if the tokenId is Type.Claim.
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
     * @return typeOfToken The enum Type of the tokenId.
     */
    function tokenType(uint256 tokenId) external view returns (Type typeOfToken);

    /**
     * @notice Check to see if an option is already initialized.
     * @param optionKey The option key to check.
     * @return initialized Whether or not the option is initialized.
     */
    function isOptionInitialized(uint160 optionKey) external view returns (bool initialized);

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
     * @return uriGenerator the address of the URI generator contract.
     */
    function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator);

    /**
     * @notice Updates the contract address for generating token URIs for Valorem positions.
     * @param newTokenURIGenerator The address of the new ITokenURIGenerator contract.
     */
    function setTokenURIGenerator(address newTokenURIGenerator) external;
}
