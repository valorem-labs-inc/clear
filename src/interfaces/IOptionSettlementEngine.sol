// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022
pragma solidity 0.8.16;

import "./ITokenURIGenerator.sol";

interface IOptionSettlementEngine {
    /*//////////////////////////////////////////////////////////////
    //  Events
    //////////////////////////////////////////////////////////////*/

    //
    // Write/Redeem events
    //

    /**
     * @notice Emitted when a claim is redeemed.
     * @param optionId The token id of the option type of the claim being redeemed.
     * @param claimId The token id of the claim being redeemed.
     * @param redeemer The address redeeming the claim.
     * @param exerciseAmountRedeemed The amount of the option.exerciseAsset redeemed.
     * @param underlyingAmountRedeemed The amount of option.underlyingAsset redeemed.
     */
    event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        uint256 exerciseAmountRedeemed,
        uint256 underlyingAmountRedeemed
    );

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

    //
    // Exercise events
    //

    /**
     * @notice Emitted when a bucket is assigned exercise.
     * @param optionId The token id of the option type exercised.
     * @param bucketIndex The index of the bucket which is being assigned exercise.
     * @param amountAssigned The amount of options contracts assigned exercise in the given bucket.
     */
    event BucketAssignedExercise(uint256 indexed optionId, uint96 indexed bucketIndex, uint112 amountAssigned);

    /**
     * @notice Emitted when option contract(s) is(are) exercised.
     * @param optionId The token id of the option type exercised.
     * @param exerciser The address that exercised the option contract(s).
     * @param amount The amount of option contracts exercised.
     */
    event OptionsExercised(uint256 indexed optionId, address indexed exerciser, uint112 amount);

    /**
     * @notice Emitted when new options contracts are written.
     * @param optionId The token id of the option type written.
     * @param writer The address of the writer.
     * @param claimId The claim token id of the new or existing short position written against.
     * @param bucketIndex The index of the bucket to which the claim was added.
     * @param amount The amount of options contracts written.
     */
    event OptionsWritten(
        uint256 indexed optionId, address indexed writer, uint256 indexed claimId, uint96 bucketIndex, uint112 amount
    );

    //
    // Fee events
    //

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

    //
    // Access control events
    //

    /**
     * @notice Emitted when feeTo address is updated.
     * @param newFeeTo The new feeTo address.
     */
    event FeeToUpdated(address indexed newFeeTo);

    /**
     * @notice Emitted when TokenURIGenerator is updated.
     * @param newTokenURIGenerator The new TokenURIGenerator address.
     */
    event TokenURIGeneratorUpdated(address indexed newTokenURIGenerator);

    /*//////////////////////////////////////////////////////////////
    //  Errors
    //////////////////////////////////////////////////////////////*/

    //
    // Access control errors
    //

    /**
     * @notice The caller doesn't have permission to access that function.
     * @param accessor The requesting address.
     * @param permissioned The address which has the requisite permissions.
     */
    error AccessControlViolation(address accessor, address permissioned);

    //
    // Input errors
    //

    /// @notice The amount of options contracts written must be greater than zero.
    error AmountWrittenCannotBeZero();

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

    /**
     * @notice This option cannot yet be exercised.
     * @param optionId Supplied option ID.
     * @param exercise The time after which the option optionId be exercised.
     */
    error ExerciseTooEarly(uint256 optionId, uint40 exercise);

    /**
     * @notice The option exercise window is too short.
     * @param exercise The timestamp supplied for exercise.
     */
    error ExerciseWindowTooShort(uint40 exercise);

    /**
     * @notice The optionId specified expired has already expired.
     * @param optionId The id of the expired option.
     * @param expiry The expiry time for the supplied option Id.
     */
    error ExpiredOption(uint256 optionId, uint40 expiry);

    /**
     * @notice The expiry timestamp is too soon.
     * @param expiry Timestamp of expiry.
     */
    error ExpiryWindowTooShort(uint40 expiry);

    /**
     * @notice Invalid (zero) address.
     * @param input The address input.
     */
    error InvalidAddress(address input);

    /**
     * @notice The assets specified are invalid or duplicate.
     * @param asset1 Supplied ERC20 asset.
     * @param asset2 Supplied ERC20 asset.
     */
    error InvalidAssets(address asset1, address asset2);

    /**
     * @notice The token specified is not a claim token.
     * @param token The supplied token id.
     */
    error InvalidClaim(uint256 token);

    /**
     * @notice The token specified is not an option token.
     * @param token The supplied token id.
     */
    error InvalidOption(uint256 token);

    /**
     * @notice This option contract type already exists and thus cannot be created.
     * @param optionId The token id of the option type which already exists.
     */
    error OptionsTypeExists(uint256 optionId);

    /**
     * @notice The requested token is not found.
     * @param token The token requested.
     */
    error TokenNotFound(uint256 token);

    /*//////////////////////////////////////////////////////////////
    //  Data Structures
    //////////////////////////////////////////////////////////////*/

    /// @notice The type of an ERC1155 subtoken in the engine.
    enum TokenType {
        None,
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

    /**
     * @notice Data about a claim to a short position written on an option type.
     * When writing an amount of options of a particular type, the writer will be issued an ERC 1155 NFT
     * that represents a claim to the underlying and exercise assets, to be claimed after
     * expiry of the option. The amount of each (underlying asset and exercise asset) paid to the claimant upon
     * redeeming their claim NFT depends on the option type, the amount of options written, represented in this struct,
     * and what portion of this claim was assigned exercise, if any, before expiry.
     */
    struct Claim {
        /// @custom:member amountWritten The number of option contracts written against this claim expressed as a 1e18 scalar value.
        uint256 amountWritten;
        /// @custom:member amountExercised The amount of option contracts exercised against this claim expressed as a 1e18 scalar value.
        uint256 amountExercised;
        /// @custom:member optionId The option ID of the option type this claim is for.
        uint256 optionId;
    }

    /**
     * @notice Data about the ERC20 assets and liabilities for a given option (long) or claim (short) token,
     * in terms of the underlying and exercise ERC20 tokens.
     */
    struct Position {
        /// @custom:member underlyingAsset The address of the ERC20 underlying asset.
        address underlyingAsset;
        /// @custom:member underlyingAmount The amount, in wei, of the underlying asset represented by this position.
        int256 underlyingAmount;
        /// @custom:member exerciseAsset The address of the ERC20 exercise asset.
        address exerciseAsset;
        /// @custom:member exerciseAmount The amount, in wei, of the exercise asset represented by this position.
        int256 exerciseAmount;
    }

    /*//////////////////////////////////////////////////////////////
    //  Views
    //////////////////////////////////////////////////////////////*/

    //
    // Option information
    //

    /**
     * @notice Gets information about an option.
     * @param tokenId The tokenId of an option or claim.
     * @return optionInfo The Option for the given tokenId.
     */
    function option(uint256 tokenId) external view returns (Option memory optionInfo);

    /**
     * @notice Gets information about a claim.
     * @param claimId The tokenId of the claim.
     * @return claimInfo The Claim for the given claimId.
     */
    function claim(uint256 claimId) external view returns (Claim memory claimInfo);

    /**
     * @notice Gets information about the ERC20 token positions of an option or claim.
     * @param tokenId The tokenId of the option or claim.
     * @return positionInfo The underlying and exercise token positions for the given tokenId.
     */
    function position(uint256 tokenId) external view returns (Position memory positionInfo);

    //
    // Token information
    //

    /**
     * @notice Gets the TokenType for a given tokenId.
     * @dev Option and claim token ids are encoded as follows:
     *
     *   MSb
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┐
     *   0000 0000   0000 0000   0000 0000   0000 0000 │
     *   0000 0000   0000 0000   0000 0000   0000 0000 │ 160b option key, created Option struct hash.
     *   0000 0000   0000 0000   0000 0000   0000 0000 │
     *   0000 0000   0000 0000   0000 0000   0000 0000 │
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┘
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┐
     *   0000 0000   0000 0000   0000 0000   0000 0000 │ 96b auto-incrementing claim key.
     *   0000 0000   0000 0000   0000 0000   0000 0000 ┘
     *                                             LSb
     * This function accounts for that, and whether or not tokenId has been initialized/decommissioned yet.
     * @param tokenId The token id to get the TokenType of.
     * @return typeOfToken The enum TokenType of the tokenId.
     */
    function tokenType(uint256 tokenId) external view returns (TokenType typeOfToken);

    /**
     * @return uriGenerator the address of the URI generator contract.
     */
    function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator);

    //
    // Fee information
    //

    /**
     * @notice Gets the balance of protocol fees for a given token which have not been swept yet.
     * @param token The token for the un-swept fee balance.
     * @return The balance of un-swept fees.
     */
    function feeBalance(address token) external view returns (uint256);

    /**
     * @notice Gets the protocol fee, expressed in basis points.
     * @return fee The protocol fee.
     */
    function feeBps() external view returns (uint8 fee);

    /**
     * @notice Checks if protocol fees are enabled.
     * @return enabled Whether or not protocol fees are enabled.
     */
    function feesEnabled() external view returns (bool enabled);

    /**
     * @notice Returns the address to which protocol fees are swept.
     * @return The address to which fees are swept.
     */
    function feeTo() external view returns (address);

    /*//////////////////////////////////////////////////////////////
    //  Write Options
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Creates a new option contract type if it doesn't already exist.
     * @dev optionId can be precomputed using
     *  uint160 optionKey = uint160(
     *      bytes20(
     *          keccak256(
     *              abi.encode(
     *                  underlyingAsset,
     *                  underlyingAmount,
     *                  exerciseAsset,
     *                  exerciseAmount,
     *                  exerciseTimestamp,
     *                  expiryTimestamp,
     *                  uint160(0),
     *                  uint96(0)
     *              )
     *          )
     *      )
     *  );
     *  optionId = uint256(optionKey) << OPTION_ID_PADDING;
     * and then tokenType(optionId) == TokenType.Option if the option already exists.
     * @param underlyingAsset The contract address of the ERC20 underlying asset.
     * @param underlyingAmount The amount of underlyingAsset, in wei, collateralizing each option contract.
     * @param exerciseAsset The contract address of the ERC20 exercise asset.
     * @param exerciseAmount The amount of exerciseAsset, in wei, required to exercise each option contract.
     * @param exerciseTimestamp The timestamp after which this option can be exercised.
     * @param expiryTimestamp The timestamp before which this option can be exercised.
     * @return optionId The token id for the new option type created by this call.
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
     * @param tokenId The desired token id to write against, input an optionId to get a new claim, or a claimId
     * to add to an existing claim.
     * @param amount The desired number of option contracts to write.
     * @return claimId The token id of the claim NFT which was input or created.
     */
    function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId);

    /*//////////////////////////////////////////////////////////////
    //  Redeem Claims
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Redeems a claim NFT, transfers the underlying/exercise tokens to the caller.
     * Can be called after option expiry timestamp (inclusive).
     * @param claimId The ID of the claim to redeem.
     */
    function redeem(uint256 claimId) external;

    /*//////////////////////////////////////////////////////////////
    //  Exercise Options
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Exercises specified amount of optionId, transferring in the exercise asset,
     * and transferring out the underlying asset if requirements are met. Can be called
     * from exercise timestamp (inclusive), until option expiry timestamp (exclusive).
     * @param optionId The option token id of the option type to exercise.
     * @param amount The amount of option contracts to exercise.
     */
    function exercise(uint256 optionId, uint112 amount) external;

    /*//////////////////////////////////////////////////////////////
    //  Protocol Admin
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enables or disables protocol fees.
     * @param enabled Whether or not protocol fees should be enabled.
     */
    function setFeesEnabled(bool enabled) external;

    /**
     * @notice Nominates a new address to which fees should be swept, requiring
     * the new feeTo address to accept before the update is complete. See also
     * acceptFeeTo().
     * @param newFeeTo The new address to which fees should be swept.
     */
    function setFeeTo(address newFeeTo) external;

    /**
     * @notice Accepts the new feeTo address and completes the update.
     * See also setFeeTo(address newFeeTo).
     */
    function acceptFeeTo() external;

    /**
     * @notice Updates the contract address for generating token URIs for tokens.
     * @param newTokenURIGenerator The address of the new ITokenURIGenerator contract.
     */
    function setTokenURIGenerator(address newTokenURIGenerator) external;

    /**
     * @notice Sweeps fees to the feeTo address if there is more than 1 wei for
     * feeBalance for a given token.
     * @param tokens An array of tokens to sweep fees for.
     */
    function sweepFees(address[] memory tokens) external;
}
