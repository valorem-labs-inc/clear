// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "./IERC1155Metadata.sol";
import "./IOptionSettlementEngine.sol";

/// @title A token URI geneartor for Claim NFTs
/// @author 0xAlcibiades
/// @author Flip-Liquid
/// @author neodaoist
interface ITokenURIGenerator {
    struct TokenURIParams {
        /// @param underlyingAsset The underlying asset to be received
        address underlyingAsset;
        /// @param underlyingSymbol The symbol of the underlying asset
        string underlyingSymbol;
        /// @param exerciseAsset The address of the asset needed for exercise
        address exerciseAsset;
        /// @param exerciseSymbol The symbol of the underlying asset
        string exerciseSymbol;
        /// @param exerciseTimestamp The timestamp after which this option may be exercised
        uint40 exerciseTimestamp;
        /// @param expiryTimestamp The timestamp before which this option must be exercised
        uint40 expiryTimestamp;
        /// @param underlyingAmount The amount of the underlying asset contained within an option contract of this type
        uint96 underlyingAmount;
        /// @param exerciseAmount The amount of the exercise asset required to exercise this option
        uint96 exerciseAmount;
        /// @param tokenType Option or Claim
        IOptionSettlementEngine.Type tokenType;
    }

    function constructTokenURI(TokenURIParams memory params) external view returns (string memory);

    function generateName(TokenURIParams memory params) external pure returns (string memory);

    function generateDescription(TokenURIParams memory params) external pure returns (string memory);

    function generateNFT(TokenURIParams memory params) external view returns (string memory);
}
