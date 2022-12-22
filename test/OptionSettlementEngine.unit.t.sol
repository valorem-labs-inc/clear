// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "solmate/utils/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "./utils/BaseEngineTest.sol";

contract OptionSettlementTest is BaseEngineTest {
    // function option(uint256 tokenId) external view returns (Option memory optionInfo);

    function test_unitOptionRevertsWhenDoesNotExist() public {
        uint256 badOptionId = 123;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badOptionId));
        engine.option(badOptionId);
    }

    function test_unitOptionReturnsOptionInfo() public {
        IOptionSettlementEngine.Option memory optionInfo = engine.option(testOptionId);
        assertEq(optionInfo.underlyingAsset, testUnderlyingAsset);
        assertEq(optionInfo.underlyingAmount, testUnderlyingAmount);
        assertEq(optionInfo.exerciseAsset, testExerciseAsset);
        assertEq(optionInfo.exerciseAmount, testExerciseAmount);
        assertEq(optionInfo.exerciseTimestamp, testExerciseTimestamp);
        assertEq(optionInfo.expiryTimestamp, testExpiryTimestamp);
    }

    // function claim(uint256 claimId) external view returns (Claim memory claimInfo);

    // function position(uint256 tokenId) external view returns (Position memory positionInfo);

    // function tokenType(uint256 tokenId) external view returns (TokenType typeOfToken);

    // function tokenURIGenerator() external view returns (ITokenURIGenerator uriGenerator);

    // function feeBalance(address token) external view returns (uint256);

    // function feeBps() external view returns (uint8 fee);

    // function feesEnabled() external view returns (bool enabled);

    // function feeTo() external view returns (address);

    // function newOptionType(
    //        address underlyingAsset,
    //        uint96 underlyingAmount,
    //        address exerciseAsset,
    //        uint96 exerciseAmount,
    //        uint40 exerciseTimestamp,
    //        uint40 expiryTimestamp
    //    ) external returns (uint256 optionId);

    // function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId);

    // function redeem(uint256 claimId) external;

    // function exercise(uint256 optionId, uint112 amount) external;

    // function setFeesEnabled(bool enabled) external;

    // function setFeeTo(address newFeeTo) external;

    // function setTokenURIGenerator(address newTokenURIGenerator) external;

    // function sweepFees(address[] memory tokens) external;

    // position()
    function test_unitPositionClaim() public {}
}
