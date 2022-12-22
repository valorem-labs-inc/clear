// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./utils/BaseEngineTest.sol";

/// @notice Fuzz tests for OptionSettlementEngine
contract OptionSettlementFuzzTest is BaseEngineTest {
    struct FuzzMetadata {
        uint256 claimsLength;
        uint256 totalWritten;
        uint256 totalExercised;
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

    // TODO(Bool to flip exercise/underlying assets)
    function test_fuzzNewOptionType(
        uint96 underlyingAmount,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) public {
        vm.assume(expiryTimestamp >= block.timestamp + 86400);
        vm.assume(exerciseTimestamp >= block.timestamp);
        vm.assume(exerciseTimestamp <= expiryTimestamp - 86400);
        vm.assume(expiryTimestamp <= type(uint64).max);
        vm.assume(exerciseTimestamp <= type(uint64).max);
        vm.assume(underlyingAmount <= WETHLIKE.totalSupply());
        vm.assume(exerciseAmount <= DAILIKE.totalSupply());

        (uint256 optionId, IOptionSettlementEngine.Option memory optionInfo) = _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: underlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp
        });

        IOptionSettlementEngine.Option memory optionRecord = engine.option(optionId);

        // assert the option ID is equal to the upper 160 of the keccak256 hash
        bytes20 _optionInfoHash = bytes20(keccak256(abi.encode(optionInfo)));
        uint160 _optionId = uint160(_optionInfoHash);
        uint256 expectedOptionId = uint256(_optionId) << 96;

        assertEq(optionId, expectedOptionId);
        assertEq(optionRecord.underlyingAsset, address(WETHLIKE));
        assertEq(optionRecord.exerciseAsset, address(DAILIKE));
        assertEq(optionRecord.exerciseTimestamp, exerciseTimestamp);
        assertEq(optionRecord.expiryTimestamp, expiryTimestamp);
        assertEq(optionRecord.underlyingAmount, underlyingAmount);
        assertEq(optionRecord.exerciseAmount, exerciseAmount);

        _assertTokenIsOption(optionId);
    }

    //
    // function write(uint256 tokenId, uint112 amount) external returns (uint256 claimId);
    //

    // TODO investigate rounding error
    // [FAIL. Reason: TRANSFER_FROM_FAILED Counterexample: calldata=0xf494d5a9000000000000000000000000000000000000000000000000000000000015c992, args=[1427858]]
    function test_fuzzWrite(uint112 amount) public {
        uint256 wethBalanceEngine = WETHLIKE.balanceOf(address(engine));
        uint256 wethBalance = WETHLIKE.balanceOf(ALICE);

        vm.assume(amount > 0);
        vm.assume(amount <= wethBalance / testUnderlyingAmount);

        uint256 rxAmount = amount * testUnderlyingAmount;
        uint256 fee = ((rxAmount / 10000) * engine.feeBps());

        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, amount);
        IOptionSettlementEngine.Position memory claimPosition = engine.position(claimId);

        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + rxAmount + fee);
        assertEq(WETHLIKE.balanceOf(ALICE), wethBalance - rxAmount - fee);

        assertEq(engine.balanceOf(ALICE, testOptionId), amount);
        assertEq(engine.balanceOf(ALICE, claimId), 1);

        assertEq(uint256(claimPosition.underlyingAmount), testUnderlyingAmount * amount);

        (uint160 optionId, uint96 claimIdx) = decodeTokenId(claimId);
        assertEq(uint256(optionId) << 96, testOptionId);
        assertEq(claimIdx, 1);
        _assertClaimAmountExercised(claimId, 0);

        _assertTokenIsClaim(claimId);
    }

    //
    // function redeem(uint256 claimId) external;
    //
    function test_fuzzExercise(uint112 amountWrite, uint112 amountExercise) public {
        uint256 wethBalanceEngine = WETHLIKE.balanceOf(address(engine));
        uint256 daiBalanceEngine = DAILIKE.balanceOf(address(engine));
        uint256 wethBalance = WETHLIKE.balanceOf(ALICE);
        uint256 daiBalance = DAILIKE.balanceOf(ALICE);

        vm.assume(amountWrite > 0);
        vm.assume(amountExercise > 0);
        vm.assume(amountWrite >= amountExercise);
        vm.assume(amountWrite <= wethBalance / testUnderlyingAmount);
        vm.assume(amountExercise <= daiBalance / testExerciseAmount);

        uint256 writeAmount = amountWrite * testUnderlyingAmount;
        uint256 writeFee = ((amountWrite * testUnderlyingAmount) / 10000) * engine.feeBps();

        uint256 rxAmount = amountExercise * testExerciseAmount;
        uint256 txAmount = amountExercise * testUnderlyingAmount;
        uint256 exerciseFee = (rxAmount / 10000) * engine.feeBps();

        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWrite);

        vm.warp(testExpiryTimestamp - 1);

        engine.exercise(testOptionId, amountExercise);

        _assertClaimAmountExercised(claimId, amountExercise);

        assertEq(WETHLIKE.balanceOf(address(engine)), wethBalanceEngine + writeAmount - txAmount + writeFee);
        assertEq(WETHLIKE.balanceOf(ALICE), (wethBalance - writeAmount + txAmount - writeFee));
        assertEq(DAILIKE.balanceOf(address(engine)), daiBalanceEngine + rxAmount + exerciseFee);
        assertEq(DAILIKE.balanceOf(ALICE), (daiBalance - rxAmount - exerciseFee));
        assertEq(engine.balanceOf(ALICE, testOptionId), amountWrite - amountExercise);
        assertEq(engine.balanceOf(ALICE, claimId), 1);
    }

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

    /*//////////////////////////////////////////////////////////////
    // Function Composite Tests
    //////////////////////////////////////////////////////////////*/

    function test_fuzzWriteExerciseRedeem(uint32 seed) public {
        uint32 i = 0;
        uint256[] memory claimIds1 = new uint256[](30);
        FuzzMetadata memory opt1 = FuzzMetadata(0, 0, 0);
        uint256[] memory claimIds2 = new uint256[](90);
        FuzzMetadata memory opt2 = FuzzMetadata(0, 0, 0);

        // create monthly option
        (uint256 optionId1M, IOptionSettlementEngine.Option memory option1M) = _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });

        // create quarterly option
        (uint256 optionId3M, IOptionSettlementEngine.Option memory option3M) = _createNewOptionType({
            underlyingAsset: address(WETHLIKE),
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: address(DAILIKE),
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: uint40(block.timestamp + 90 days)
        });

        for (i = 0; i < 90; i++) {
            // loop until expiry
            unchecked {
                _writeExerciseOptions(seed, option1M, optionId1M, claimIds1, opt1);
                seed += 10;
                _writeExerciseOptions(seed++, option3M, optionId3M, claimIds2, opt2);
                seed += 10;
            }

            // advance 1 d
            vm.warp(block.timestamp + 1 days);
        }

        // claim
        for (i = 0; i < opt1.claimsLength - 1; i++) {
            uint256 claimId = claimIds1[i];
            _claimAndAssert(ALICE, claimId);
        }

        for (i = 0; i < opt2.claimsLength - 1; i++) {
            uint256 claimId = claimIds2[i];
            _claimAndAssert(ALICE, claimId);
        }
    }

    /*//////////////////////////////////////////////////////////////
    //  Helper Functions -- Working with Options, Claims, etc.
    //////////////////////////////////////////////////////////////*/

    function _writeExerciseOptions(
        uint32 seed,
        IOptionSettlementEngine.Option memory option1M,
        uint256 optionId1M,
        uint256[] memory claimIds1,
        FuzzMetadata memory opt1
    ) internal {
        (uint256 written, uint256 exercised, bool newClaim) = _writeExercise(
            ALICE,
            BOB,
            seed,
            5000, // write chance bips
            1,
            5000, // exercise chance bips
            option1M,
            optionId1M,
            claimIds1,
            opt1.claimsLength
        );
        if (newClaim) {
            opt1.claimsLength += 1;
        }
        opt1.totalWritten += written;
        opt1.totalExercised += exercised;
    }

    function _claimAndAssert(address claimant, uint256 claimId) internal {
        vm.startPrank(claimant);

        IOptionSettlementEngine.Position memory position = engine.position(claimId);
        uint256 exerciseAssetAmount = ERC20(position.exerciseAsset).balanceOf(claimant);
        uint256 underlyingAssetAmount = ERC20(position.underlyingAsset).balanceOf(claimant);
        engine.redeem(claimId);

        assertEq(
            ERC20(position.underlyingAsset).balanceOf(claimant),
            underlyingAssetAmount + uint256(position.underlyingAmount)
        );
        assertEq(
            ERC20(position.exerciseAsset).balanceOf(claimant), exerciseAssetAmount + uint256(position.exerciseAmount)
        );
        vm.stopPrank();
    }

    function _writeExercise(
        address writer,
        address exerciser,
        uint32 seed,
        uint16 writeChanceBips,
        uint16 maxWrite,
        uint16 exerciseChanceBips,
        IOptionSettlementEngine.Option memory option,
        uint256 optionId,
        uint256[] memory claimIds,
        uint256 claimIdLength
    ) internal returns (uint256 written, uint256 exercised, bool newClaim) {
        if (option.expiryTimestamp <= uint40(block.timestamp)) {
            return (0, 0, false);
        }

        // with X pctg chance, write some amount of options
        unchecked {
            // allow seed to overflow
            if (_coinflip(seed++, writeChanceBips)) {
                uint16 toWrite = uint16(1 + _randBetween(seed++, maxWrite));
                emit log_named_uint("WRITING", optionId);
                emit log_named_uint("amount", toWrite);
                vm.startPrank(writer);
                // 50/50 to add to existing claim lot or create new claim lot
                if (claimIdLength == 0 || _coinflip(seed++, 5000)) {
                    newClaim = true;
                    uint256 claimId = engine.write(optionId, toWrite);
                    emit log_named_uint("ADD NEW CLAIM", claimId);
                    claimIds[claimIdLength] = claimId;
                } else {
                    uint256 claimId = claimIds[_randBetween(seed++, claimIdLength)];
                    emit log_named_uint("ADD EXISTING CLAIM", claimId);
                    engine.write(claimId, toWrite);
                }

                // add to total written
                written += toWrite;

                // transfer to exerciser
                engine.safeTransferFrom(writer, exerciser, optionId, written, "");
                vm.stopPrank();
            } else {
                emit log_named_uint("SKIP WRITING", optionId);
            }
        }

        if (option.exerciseTimestamp >= uint40(block.timestamp)) {
            emit log_named_uint("exercise timestamp not hit", option.exerciseTimestamp);
            return (written, 0, newClaim);
        }

        uint256 maxToExercise = engine.balanceOf(exerciser, optionId);
        // with Y pctg chance, exercise some amount of options
        unchecked {
            // allow seed to overflow
            if (maxToExercise != 0 && _coinflip(seed++, exerciseChanceBips)) {
                // check that we're not exercising more than have been written
                emit log_named_uint("EXERCISING", optionId);
                uint16 toExercise = uint16(1 + _randBetween(seed++, maxToExercise));
                emit log_named_uint("amount", toExercise);

                vm.prank(exerciser);
                engine.exercise(optionId, toExercise);

                // add to total exercised
                exercised += toExercise;
            } else {
                emit log_named_uint("SKIP EXERCISING", optionId);
            }
        }
    }
}
