// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

// @author 0xAlcibiades
interface IOptionSettlementEngine {
    event FeeSwept(
        address indexed token,
        address indexed feeTo,
        uint256 amount
    );

    event NewChain(
        uint256 indexed optionId,
        address indexed exerciseAsset,
        address indexed underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    );

    event OptionsExercised(
        uint256 indexed optionId,
        address indexed exercisee,
        uint112 amount
    );

    event OptionsWritten(
        uint256 indexed optionId,
        address indexed writer,
        uint256 claimId,
        uint112 amount
    );

    event FeeAccrued(
        address indexed asset,
        address indexed payor,
        uint256 amount
    );

    event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        address exerciseAsset,
        address underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount
    );

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

    struct Underlying {
        address underlyingAsset;
        int256 underlyingPosition;
        address exerciseAsset;
        int256 exercisePosition;
    }

    // @notice The protocol fee, expressed in basis points
    // @return The fee in basis points
    function feeBps() external view returns (uint8);

    // @return The address fees accrue to
    function feeTo() external view returns (address);

    // @return The balance of unswept fees for a given address
    function feeBalance(address token) external view returns (uint256);

    // @return The enum (uint8) Type of the tokenId
    function tokenType(uint256 tokenId) external view returns (Type);

    // @return The optionInfo Option struct for tokenId
    function option(uint256 tokenId)
        external
        view
        returns (Option memory optionInfo);

    // @return The claimInfo Claim struct for claimId
    function claim(uint256 tokenId)
        external
        view
        returns (Claim memory claimInfo);

    // @notice Updates the address fees can be swept to
    function setFeeTo(address newFeeTo) external;

    // @return The tokenId if it exists, else 0
    function hashToOptionToken(bytes32 hash)
        external
        view
        returns (uint256 optionId);

    // @notice Sweeps fees to the feeTo address if there are more than 0 wei for each address in tokens
    function sweepFees(address[] memory tokens) external;

    // @notice Create a new options chain from optionInfo if it doesn't already exist
    function newChain(Option memory optionInfo)
        external
        returns (uint256 optionId);

    // @notice write a new bundle of options contract and recieve options tokens and claim ticket
    function write(uint256 optionId, uint112 amount)
        external
        returns (uint256 claimId);

    // @notice exercise amount of optionId transfers and receives required amounts of tokens
    function exercise(uint256 optionId, uint112 amount) external;

    // @notice redeem a claim NFT, transfers the underlying tokens
    function redeem(uint256 claimId) external;

    // TODO(Nail down the structure here)
    // @notice Information about the position underlying a token, useful for determining value
    function underlying(uint256 tokenId)
        external
        view
        returns (Underlying memory underlyingPositions);
}
