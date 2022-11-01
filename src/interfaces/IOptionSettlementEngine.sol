// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "./IERC1155Metadata.sol";

/// @title A settlement engine for options
/// @author 0xAlcibiades
interface IOptionSettlementEngine {
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
     * @param feeTo the feeTo address.
     */
    error InvalidFeeToAddress(address feeTo);

    /**
     * @notice This options chain already exists and thus cannot be created.
     * @param optionId The id and hash of the options chain.
     */
    error OptionsTypeExists(uint256 optionId);

    /**
     * @notice The expiry timestamp is less than 24 hours from now.
     * @param optionId Supplied option ID.
     * @param expiry Timestamp of expiry
     */
    error ExpiryTooSoon(uint256 optionId, uint40 expiry);

    /// @notice The option exercise window is less than 24 hours long.
    error ExerciseWindowTooShort();

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
     * @notice Provided claimId does not match provided option id in the upper 160b
     * encoding the corresponding option ID for which the claim was written.
     * @param claimId The provided claim ID.
     * @param optionId The provided option ID.
     */
    error EncodedOptionIdInClaimIdDoesNotMatchProvidedOptionId(uint256 claimId, uint256 optionId);

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
     * @notice This option has no claims written against it.
     * @param optionId Supplied option ID.
     */
    error NoClaims(uint256 optionId);

    /**
     * @notice This claim is not owned by the caller.
     * @param claimId Supplied claim ID.
     */
    error CallerDoesNotOwnClaimId(uint256 claimId);

    /**
     * @notice This claimId has already been claimed.
     * @param claimId Supplied claim ID.
     */
    error AlreadyClaimed(uint256 claimId);

    /**
     * @notice You can't claim before expiry.
     * @param claimId Supplied claim ID.
     * @param expiry timestamp at which the options chain expires
     */
    error ClaimTooSoon(uint256 claimId, uint40 expiry);

    /// @notice The amount provided to write() must be > 0.
    error AmountWrittenCannotBeZero();

    /**
     * @notice Emitted when accrued protocol fees for a given token are swept to the
     * feeTo address.
     * @param token The token for which protocol fees are being swept.
     * @param feeTo The account to which fees are being swept.
     * @param amount The total amount being swept.
     */
    event FeeSwept(address indexed token, address indexed feeTo, uint256 amount);

    /**
     * @notice Emitted when a new unique options type is created.
     * @param optionId The id of the initial option created.
     * @param exerciseAsset The contract address of the exercise asset.
     * @param underlyingAsset The contract address of the underlying asset.
     * @param exerciseAmount The amount of the exercise asset to be exercised.
     * @param underlyingAmount The amount of the underlying asset in the option.
     * @param exerciseTimestamp The timestamp for exercising the option.
     * @param expiryTimestamp The expiry timestamp of the option.
     * @param nextClaimId The next claim ID.
     */
    event NewOptionType(
        uint256 indexed optionId,
        address indexed exerciseAsset,
        address indexed underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp,
        uint96 nextClaimId
    );

    /**
     * @notice Emitted when an option is exercised.
     * @param optionId The id of the option being exercised.
     * @param exercisee The contract address of the asset being exercised.
     * @param amount The amount of the exercissee being exercised.
     */
    event OptionsExercised(uint256 indexed optionId, address indexed exercisee, uint112 amount);

    /**
     * @notice Emitted when a new option is written.
     * @param optionId The id of the newly written option.
     * @param writer The address of the writer of the new option.
     * @param claimId The claim ID for the option.
     * @param amount The amount of options written.
     */
    event OptionsWritten(uint256 indexed optionId, address indexed writer, uint256 indexed claimId, uint112 amount);

    /**
     * @notice Emitted when protocol fees are accrued for a given asset.
     * @dev Emitted on write() when fees are accrued on the underlying asset,
     * or exercise() when fees are accrued on the exercise asset.
     * @param asset Asset for which fees are accrued.
     * @param payor The address paying the fee.
     * @param amount The amount of fees which are accrued.
     */
    event FeeAccrued(address indexed asset, address indexed payor, uint256 amount);

    /**
     * @notice Emitted when a claim is redeemed.
     * @param claimId The id of the claim being redeemed.
     * @param optionId The option id associated with the redeeming claim.
     * @param redeemer The address redeeming the claim.
     * @param exerciseAsset The exercise asset of the option.
     * @param underlyingAsset The underlying asset of the option.
     * @param exerciseAmount The amount of options being
     * @param underlyingAmount The amount of underlying
     */
    event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        address exerciseAsset,
        address underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount
    );

    /**
     * @notice Emitted when an option id is exercised and assigned to a particular claim NFT.
     * @param claimId The claim NFT id being assigned.
     * @param optionId The id of the option being exercised.
     * @param amountAssigned The total amount of options contracts assigned.
     */
    event ExerciseAssigned(uint256 indexed claimId, uint256 indexed optionId, uint112 amountAssigned);

    /// @dev This enumeration is used to determine the type of an ERC1155 subtoken in the engine.
    enum Type {
        None,
        Option,
        Claim
    }

    /// @dev This struct contains the data about an options type associated with an ERC-1155 token.
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
        // Random seed created at the time of option type creation
        uint160 settlementSeed;
        // The amount of the exercise asset required to exercise this option
        uint96 exerciseAmount;
        // Which option was written
        uint96 nextClaimId;
    }

    /// @dev This struct contains the data about a claim ERC-1155 NFT associated with an option type.
    struct Claim {
        // These are 1:1 contracts with the underlying Option struct
        // The number of contracts written in this claim
        uint112 amountWritten;
        // The two amounts above along with the option info, can be used to calculate the underlying assets
        bool claimed;
    }

    /// @dev Claims are options lots which are able to have options added to them on different
    /// bucketed days. This struct is used to keep track of how many options in a single lot are
    /// written on each day, in order to correctly perform fair assignment.
    struct ClaimIndex {
        // The amount of options written on a given day
        uint112 amountWritten;
        // The index of the bucket on which the options are written
        uint16 bucketIndex;
    }

    /// @dev Represents the total amount of options written and exercised for a group of
    /// claims bucketed by day. Used in fair assignement to calculate the ratio of
    /// underlying to exercise assets to be transferred to claimants.
    struct ClaimBucket {
        // The number of options written in this bucket
        uint112 amountWritten;
        // The number of options exercised in this bucket
        uint112 amountExercised;
        // Which day this bucket falls on, in offset from epoch
        uint16 daysAfterEpoch;
    }

    /// @dev Struct used in returning data regarding positions underlying a claim or option
    struct Underlying {
        // address of the underlying asset erc20
        address underlyingAsset;
        // position on the underlying asset
        int256 underlyingPosition;
        // address of the exercise asset erc20
        address exerciseAsset;
        // position on the exercise asset
        int256 exercisePosition;
    }

    /**
     * @notice The balance of protocol fees for a given token which have not yet
     * been swept.
     * @param token The token for the unswept fee balance.
     * @return The balance of unswept fees.
     */
    function feeBalance(address token) external view returns (uint256);

    /**
     * @notice The protocol fee, expressed in basis points.
     * @return The fee in basis points.
     */
    function feeBps() external view returns (uint8);

    /**
     * @notice Returns the address to which protocol fees are swept.
     * @return The address to which fees are swept
     */
    function feeTo() external view returns (address);

    /**
     * @notice Returns the token type (e.g. Option/Claim) for a given token Id
     * @param tokenId The id of the option or claim.
     * @return The enum (uint8) Type of the tokenId
     */
    function tokenType(uint256 tokenId) external view returns (Type);

    /**
     * @notice Returns Option struct details about a given tokenID if that token is
     * an option.
     * @param tokenId The id of the option.
     * @return optionInfo The Option struct for tokenId.
     */
    function option(uint256 tokenId) external view returns (Option memory optionInfo);

    /**
     * @notice Returns Claim struct details about a given tokenId if that token is a
     * claim NFT.
     * @param tokenId The id of the claim.
     * @return claimInfo The Claim struct for tokenId.
     */
    function claim(uint256 tokenId) external view returns (Claim memory claimInfo);

    /**
     * @notice Returns the total amount of options written and exercised for all claims /
     * option lots created on the supplied index.
     * @param optionId The id of the option for the claim buckets.
     * @param dayBucket The index of the claimBucket to return.
     */
    function claimBucket(uint256 optionId, uint16 dayBucket)
        external
        view
        returns (ClaimBucket memory claimBucketInfo);

    /**
     * @notice Updates the address fees can be swept to.
     * @param newFeeTo The new address to which fees will be swept.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Sweeps fees to the feeTo address if there are more than 0 wei for
     * each address in tokens.
     * @param tokens The tokens for which fees will be swept to the feeTo address.
     */
    function sweepFees(address[] memory tokens) external;

    /**
     * @notice Create a new options type from optionInfo if it doesn't already exist
     * @dev The supplied creation timestamp and next claim Id fields will be disregarded.
     * @param optionInfo The optionInfo from which a new type will be created
     * @return optionId The optionId for the option.
     */
    function newOptionType(Option memory optionInfo) external returns (uint256 optionId);

    /**
     * @notice Writes a specified amount of the specified option, returning claim NFT id.
     * @param optionId The desired option id to write.
     * @param amount The desired number of options to write.
     * @return claimId The claim NFT id for the option bundle.
     */
    function write(uint256 optionId, uint112 amount) external returns (uint256 claimId);

    /**
     * @notice This override allows additional options to be written against a particular
     * claim id.
     * @param optionId The desired option id to write.
     * @param amount The desired number of options to write.
     * @param claimId The claimId for the options lot to which the caller will add options
     * @return claimId The claim NFT id for the option bundle.
     */
    function write(uint256 optionId, uint112 amount, uint256 claimId) external returns (uint256);

    /**
     * @notice Exercises specified amount of optionId, transferring in the exercise asset,
     * and transferring out the underlying asset if requirements are met. Will revert with
     * an underflow/overflow if the user does not have the required assets.
     * @param optionId The option id to exercise.
     * @param amount The amount of option id to exercise.
     */
    function exercise(uint256 optionId, uint112 amount) external;

    /**
     * @notice Redeem a claim NFT, transfers the underlying tokens.
     * @param claimId The ID of the claim to redeem.
     */
    function redeem(uint256 claimId) external;

    /**
     * @notice Information about the position underlying a token, useful for determining
     * value.
     * @param tokenId The token id for which to retrieve the Underlying position.
     * @return underlyingPositions The Underlying struct for the supplied tokenId.
     */
    function underlying(uint256 tokenId) external view returns (Underlying memory underlyingPositions);
}
