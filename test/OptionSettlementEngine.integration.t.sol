// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./utils/BaseEngineTest.sol";

/// @notice Integration tests for OptionSettlementEngine
contract OptionSettlementIntegrationTest is BaseEngineTest {
    // TODO(Delete when there is at least 1 test)
    function test_integrationInitial() public {
        assertEq(engine.feeTo(), FEE_TO);
        assertEq(engine.feesEnabled(), true);
    }

    //
    // function option(uint256 tokenId) external view returns (Option memory optionInfo);
    //

    //
    // function claim(uint256 claimId) external view returns (Claim memory claimInfo);
    //

    //
    // function position(uint256 tokenId) external view returns (Position memory positionInfo);
    //

    //
    // function tokenType(uint256 tokenId) external view returns (TokenType typeOfToken);
    //

    //
    // function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator);
    //

    //
    // function feeBalance(address token) external view returns (uint256);
    //

    //
    // function feeBps() external view returns (uint8 fee);
    //

    //
    // function feesEnabled() external view returns (bool enabled);
    //

    //
    // function feeTo() external view returns (address);
    //

    //
    // function newOptionType(
    //        address underlyingAsset,
    //        uint96 underlyingAmount,
    //        address exerciseAsset,
    //        uint96 exerciseAmount,
    //        uint40 exerciseTimestamp,
    //        uint40 expiryTimestamp
    //    ) external returns (uint256 optionId);
    //

    //
    // function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId);
    //

    //
    // function redeem(uint256 claimId) external;
    //

    //
    // function exercise(uint256 optionId, uint112 amount) external;

    //
    // function setFeesEnabled(bool enabled) external;

    //
    // function setFeeTo(address newFeeTo) external;

    //
    // function setTokenURIGenerator(address newTokenURIGenerator) external;
    //

    //
    // function sweepFees(address[] memory tokens) external;
    //
}
