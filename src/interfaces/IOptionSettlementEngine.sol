// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

// @author 0xAlcibiades
interface IOptionSettlementEngine {
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

    function newChain(Option memory optionInfo)
        external
        returns (uint256 optionId);
}
