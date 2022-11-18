// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "forge-std/Test.sol";
import "./interfaces/IERC20.sol";
import "../src/OptionSettlementEngine.sol";

/// @notice Receiver hook utility for NFT 'safe' transfers
abstract contract NFTreceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return 0xbc197c81;
    }
}

contract OptionSettlementTest is Test, NFTreceiver {
    using stdStorage for StdStorage;

    OptionSettlementEngine public engine;

    // Tokens
    address public constant WETH_A = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI_A = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC_A = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Admin
    address public constant FEE_TO = 0x2dbd50A4Ef9B172698596217b7DB0163D3607b41;

    // Users
    address public constant ALICE = address(0xA);
    address public constant BOB = address(0xB);
    address public constant CAROL = address(0xC);

    // Token interfaces
    IERC20 public constant DAI = IERC20(DAI_A);
    IERC20 public constant WETH = IERC20(WETH_A);
    IERC20 public constant USDC = IERC20(USDC_A);

    // Test option
    uint256 private testOptionId;
    address private testUnderlyingAsset = WETH_A;
    uint40 private testExerciseTimestamp;
    uint40 private testExpiryTimestamp;
    address private testExerciseAsset = DAI_A;
    uint96 private testUnderlyingAmount = 7 ether; // NOTE: uneven number to test for division rounding
    uint96 private testExerciseAmount = 3000 ether;
    uint256 private testDuration = 1 days;

    IOptionSettlementEngine.Option private testOption;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("RPC_URL"), 15_000_000); // specify block number to cache for future test runs

        // Deploy OptionSettlementEngine
        engine = new OptionSettlementEngine(FEE_TO);

        // Setup test option contract
        testExerciseTimestamp = uint40(block.timestamp);
        testExpiryTimestamp = uint40(block.timestamp + testDuration);
        (testOptionId, testOption) = _createNewOptionType({
            underlyingAsset: testUnderlyingAsset,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: testExerciseAsset,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        // Pre-load balances and approvals
        address[3] memory recipients = [ALICE, BOB, CAROL];
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];

            // Now we have 1B in stables and 10M WETH
            _writeTokenBalance(recipient, DAI_A, 1000000000 * 1e18);
            _writeTokenBalance(recipient, USDC_A, 1000000000 * 1e6);
            _writeTokenBalance(recipient, WETH_A, 10000000 * 1e18);

            // Approve settlement engine to spend ERC20 token balances
            vm.startPrank(recipient);
            WETH.approve(address(engine), type(uint256).max);
            DAI.approve(address(engine), type(uint256).max);
            USDC.approve(address(engine), type(uint256).max);
            vm.stopPrank();
        }

        // Approve test contract approval for all on settlement engine ERC1155 token balances
        engine.setApprovalForAll(address(this), true);
    }

    function testInitial() public {
        assertEq(engine.feeTo(), FEE_TO);
    }

    // **********************************************************************
    //                            PASS TESTS
    // **********************************************************************

    function testExerciseBeforeExpiry() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 1);
        vm.stopPrank();

        assertEq(engine.balanceOf(BOB, testOptionId), 0);
    }

    function testWriteMultipleWriteSameOptionType() public {
        IOptionSettlementEngine.OptionLotClaim memory claim;

        // Alice writes a few options and later decides to write more
        vm.startPrank(ALICE);
        uint256 claimId1 = engine.write(testOptionId, 69);
        vm.warp(block.timestamp + 100);
        uint256 claimId2 = engine.write(testOptionId, 100);
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, testOptionId), 169);
        assertEq(engine.balanceOf(ALICE, claimId1), 1);
        assertEq(engine.balanceOf(ALICE, claimId2), 1);

        claim = engine.claim(claimId1);
        (uint160 _optionId, uint96 claimIdx) = engine.decodeTokenId(claimId1);
        uint256 optionId = uint256(_optionId) << 96;
        assertEq(optionId, testOptionId);
        assertEq(claimIdx, 1);
        assertEq(claim.amountWritten, 69);
        _assertClaimAmountExercised(claimId1, 0);
        assertTrue(!claim.claimed);

        claim = engine.claim(claimId2);
        (optionId, claimIdx) = engine.decodeTokenId(claimId2);
        optionId = uint256(_optionId) << 96;
        assertEq(optionId, testOptionId);
        assertEq(claimIdx, 2);
        assertEq(claim.amountWritten, 100);
        _assertClaimAmountExercised(claimId2, 0);
        assertTrue(!claim.claimed);
    }

    function testTokenURI() public view {
        engine.uri(testOptionId);
    }

    function testExerciseMultipleWriteSameChain() public {
        uint256 wethBalanceEngine = WETH.balanceOf(address(engine));
        uint256 wethBalanceA = WETH.balanceOf(ALICE);
        uint256 wethBalanceB = WETH.balanceOf(BOB);
        uint256 daiBalanceEngine = DAI.balanceOf(address(engine));
        uint256 daiBalanceA = DAI.balanceOf(ALICE);
        uint256 daiBalanceB = DAI.balanceOf(BOB);

        // Alice writes 1, decides to write another, and sends both to Bob to exercise
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 2, "");
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, testOptionId), 0);
        assertEq(engine.balanceOf(BOB, testOptionId), 2);

        // Fees
        uint256 writeAmount = 2 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount / 10000) * engine.feeBps();

        uint256 exerciseAmount = 2 * testExerciseAmount;
        uint256 exerciseFee = (exerciseAmount / 10000) * engine.feeBps();

        assertEq(WETH.balanceOf(address(engine)), wethBalanceEngine + writeAmount + writeFee);

        vm.warp(testExpiryTimestamp - 1);
        // Bob exercises
        vm.prank(BOB);
        engine.exercise(testOptionId, 2);
        assertEq(engine.balanceOf(BOB, testOptionId), 0);

        assertEq(WETH.balanceOf(address(engine)), wethBalanceEngine + writeFee);
        assertEq(WETH.balanceOf(ALICE), wethBalanceA - writeAmount - writeFee);
        assertEq(WETH.balanceOf(BOB), wethBalanceB + writeAmount);
        assertEq(DAI.balanceOf(address(engine)), daiBalanceEngine + exerciseAmount + exerciseFee);
        assertEq(DAI.balanceOf(ALICE), daiBalanceA);
        assertEq(DAI.balanceOf(BOB), daiBalanceB - exerciseAmount - exerciseFee);
    }

    function testExerciseIncompleteExercise() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 100);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 100, "");
        vm.stopPrank();

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(testOptionId, 50);

        // Bob exercises again
        engine.exercise(testOptionId, 50);
        vm.stopPrank();

        assertEq(engine.balanceOf(BOB, testOptionId), 0);
    }

    // NOTE: This test needed as testFuzz_redeem does not check if exerciseAmount == 0
    function testRedeemNotExercised() public {
        IOptionSettlementEngine.OptionLotClaim memory claimRecord;
        uint256 wethBalanceEngine = WETH.balanceOf(address(engine));
        uint256 wethBalanceA = WETH.balanceOf(ALICE);
        // Alice writes 7 and no one exercises
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 7);

        vm.warp(testExpiryTimestamp + 1);

        claimRecord = engine.claim(claimId);
        assertTrue(!claimRecord.claimed);
        engine.redeem(claimId);

        claimRecord = engine.claim(claimId);
        assertTrue(claimRecord.claimed);

        // Fees
        uint256 writeAmount = 7 * testUnderlyingAmount;
        uint256 writeFee = (writeAmount / 10000) * engine.feeBps();
        assertEq(WETH.balanceOf(ALICE), wethBalanceA - writeFee);
        assertEq(WETH.balanceOf(address(engine)), wethBalanceEngine + writeFee);
    }

    function testExerciseWithDifferentDecimals() public {
        // Write an option where one of the assets isn't 18 decimals
        (uint256 newOptionId,) = _createNewOptionType({
            underlyingAsset: USDC_A,
            underlyingAmount: 100,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        // Alice writes
        vm.startPrank(ALICE);
        engine.write(newOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, newOptionId, 1, "");
        vm.stopPrank();

        // Bob owns 1 of these options
        assertEq(engine.balanceOf(BOB, newOptionId), 1);

        // Fast-forward to just before expiry
        vm.warp(testExpiryTimestamp - 1 seconds);

        // Bob exercises
        vm.startPrank(BOB);
        engine.exercise(newOptionId, 1);
        vm.stopPrank();

        // Now Bob owns 0 of these options
        assertEq(engine.balanceOf(BOB, newOptionId), 0);
    }

    function testUnderlyingWhenNotExercised() public {
        // Alice writes 7 and no one exercises
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 7);

        vm.warp(testExpiryTimestamp + 1);

        IOptionSettlementEngine.Underlying memory underlyingPositions = engine.underlying(claimId);

        assertEq(underlyingPositions.underlyingAsset, WETH_A);
        _assertPosition(underlyingPositions.underlyingPosition, 7 * testUnderlyingAmount);
        assertEq(underlyingPositions.exerciseAsset, DAI_A);
        assertEq(underlyingPositions.exercisePosition, 0);
    }

    function testUnderlyingAfterExercise() public {
        uint256 claimId = _writeAndExerciseOption(testOptionId, ALICE, BOB, 2, 0);
        IOptionSettlementEngine.Underlying memory underlyingPositions = engine.underlying(claimId);
        _assertPosition(underlyingPositions.underlyingPosition, 2 * testUnderlyingAmount);
        assertEq(underlyingPositions.exercisePosition, 0);

        _writeAndExerciseOption(testOptionId, ALICE, BOB, 0, 1);
        underlyingPositions = engine.underlying(claimId);
        _assertPosition(underlyingPositions.underlyingPosition, testUnderlyingAmount);
        _assertPosition(underlyingPositions.exercisePosition, testExerciseAmount);

        _writeAndExerciseOption(testOptionId, ALICE, BOB, 0, 1);
        underlyingPositions = engine.underlying(claimId);
        _assertPosition(underlyingPositions.underlyingPosition, 0);
        _assertPosition(underlyingPositions.exercisePosition, 2 * testExerciseAmount);
    }

    function testUnderlyingForFungibleOptionToken() public {
        IOptionSettlementEngine.Underlying memory underlying = engine.underlying(testOptionId);
        // before expiry, position is entirely the underlying amount
        _assertPosition(underlying.underlyingPosition, testUnderlyingAmount);
        _assertPosition(-1 * underlying.exercisePosition, testExerciseAmount);
        assertEq(testExerciseAsset, underlying.exerciseAsset);
        assertEq(testUnderlyingAsset, underlying.underlyingAsset);

        vm.warp(testOption.expiryTimestamp);
        underlying = engine.underlying(testOptionId);
        _assertPosition(underlying.underlyingPosition, 0);
        _assertPosition(underlying.exercisePosition, 0);
        assertEq(testExerciseAsset, underlying.exerciseAsset);
        assertEq(testUnderlyingAsset, underlying.underlyingAsset);
    }

    function testAddOptionsToExistingClaim() public {
        // write some options, grab a claim
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        IOptionSettlementEngine.OptionLotClaim memory claimRecord = engine.claim(claimId);

        assertEq(1, claimRecord.amountWritten);
        _assertClaimAmountExercised(claimId, 0);
        assertEq(false, claimRecord.claimed);
        assertEq(1, engine.balanceOf(ALICE, claimId));
        assertEq(1, engine.balanceOf(ALICE, testOptionId));

        // write some more options, get a new claim NFT
        uint256 claimId2 = engine.write(testOptionId, 1);
        assertFalse(claimId == claimId2);
        assertEq(1, engine.balanceOf(ALICE, claimId2));
        assertEq(2, engine.balanceOf(ALICE, testOptionId));

        // write some more options, adding to existing claim
        uint256 claimId3 = engine.write(testOptionId, 1, claimId);
        assertEq(claimId, claimId3);
        assertEq(1, engine.balanceOf(ALICE, claimId3));
        assertEq(3, engine.balanceOf(ALICE, testOptionId));

        claimRecord = engine.claim(claimId3);
        assertEq(2, claimRecord.amountWritten);
        _assertClaimAmountExercised(claimId, 0);
        assertEq(false, claimRecord.claimed);
    }

    function testAssignMultipleBuckets() public {
        // New option type with expiry in 5d
        testExerciseTimestamp = uint40(block.timestamp + 1 days);
        testExpiryTimestamp = uint40(block.timestamp + 5 * 1 days);

        (uint256 optionId, IOptionSettlementEngine.Option memory option) = _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        // Alice writes some options
        vm.startPrank(ALICE);
        uint256 claimId1 = engine.write(optionId, 69);

        // write more 1d later
        vm.warp(block.timestamp + (1 days + 1));
        uint256 claimId2 = engine.write(optionId, 100);

        assertEq(169, engine.balanceOf(ALICE, optionId));

        // Alice 'sells' half the written options to Bob, half to Carol
        uint112 bobOptionAmount = 85;
        engine.safeTransferFrom(ALICE, BOB, optionId, bobOptionAmount, "");
        engine.safeTransferFrom(ALICE, CAROL, optionId, 84, "");
        assertEq(0, engine.balanceOf(ALICE, optionId));

        vm.stopPrank();

        // Bob exercises the options
        uint112 bobExerciseAmount = 70;
        uint256 bobBalanceExerciseAsset1 = ERC20(option.exerciseAsset).balanceOf(BOB);
        uint256 bobBalanceUnderlyingAsset1 = ERC20(option.underlyingAsset).balanceOf(BOB);
        uint256 bobExerciseFee = (bobExerciseAmount * option.exerciseAmount / 10000) * engine.feeBps();
        vm.startPrank(BOB);
        engine.exercise(optionId, bobExerciseAmount);
        assertEq(bobOptionAmount - bobExerciseAmount, engine.balanceOf(BOB, optionId));
        // Bob transfers in exactly (#options exercised * exerciseAmount) of the exercise asset
        // Bob receives exactly (#options exercised * underlyingAmount) - fee of the underlying asset
        assertEq(
            bobBalanceExerciseAsset1 - (bobExerciseAmount * option.exerciseAmount) - bobExerciseFee,
            ERC20(option.exerciseAsset).balanceOf(BOB)
        );
        assertEq(
            bobBalanceUnderlyingAsset1 + (bobExerciseAmount * option.underlyingAmount),
            ERC20(option.underlyingAsset).balanceOf(BOB)
        );
        vm.stopPrank();

        // randomly seeded based on option type seed. asserts will fail if seed
        // algo changes.
        // first lot is completely un exercised
        emit log_named_int("claimId1 exercise", engine.underlying(claimId1).exercisePosition);
        emit log_named_int("claimId1 underlying", engine.underlying(claimId1).underlyingPosition);

        _assertClaimAmountExercised(claimId1, 69);
        _assertClaimAmountExercised(claimId2, 1);

        // Jump ahead to option expiry
        vm.warp(1 + option.expiryTimestamp);
        vm.startPrank(ALICE);
        uint256 aliceBalanceExerciseAsset = ERC20(option.exerciseAsset).balanceOf(ALICE);
        uint256 aliceBalanceUnderlyingAsset = ERC20(option.underlyingAsset).balanceOf(ALICE);
        // Alice's first claim should be completely exercised
        engine.redeem(claimId1);
        assertEq(ERC20(option.exerciseAsset).balanceOf(ALICE), aliceBalanceExerciseAsset + 69 * option.exerciseAmount);
        assertEq(aliceBalanceUnderlyingAsset, ERC20(option.underlyingAsset).balanceOf(ALICE));

        aliceBalanceExerciseAsset = ERC20(option.exerciseAsset).balanceOf(ALICE);
        aliceBalanceUnderlyingAsset = ERC20(option.underlyingAsset).balanceOf(ALICE);

        // BOB exercised 70 options
        // ALICE should retrieve 70 * exerciseAmount of the exercise asset
        // ALICE should retrieve (100-70) * underlyingAmount of the underlying asset
        engine.redeem(claimId2);
        assertEq(ERC20(option.exerciseAsset).balanceOf(ALICE), aliceBalanceExerciseAsset + 1 * option.exerciseAmount);
        assertEq(
            ERC20(option.underlyingAsset).balanceOf(ALICE), aliceBalanceUnderlyingAsset + 99 * option.underlyingAmount
        );
    }

    function testRandomAssignment() public {
        uint16 numDays = 7;
        uint256[] memory claimIds = new uint256[](numDays);
        // New option type with expiry in 1w
        testExerciseTimestamp = uint40(block.timestamp - 1);
        testExpiryTimestamp = uint40(block.timestamp + numDays * 1 days + 1);
        (uint256 optionId,) = _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount + 1, // to mess w seed
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        vm.startPrank(ALICE);
        for (uint256 i = 0; i < numDays; i++) {
            // write a single option
            uint256 claimId = engine.write(optionId, 1);
            claimIds[i] = claimId;
            vm.warp(block.timestamp + 1 days);
        }
        engine.safeTransferFrom(ALICE, BOB, optionId, numDays, "");
        vm.stopPrank();

        vm.startPrank(BOB);

        // assign a single option on day 2
        engine.exercise(optionId, 1);
        _assertClaimAmountExercised(claimIds[0], 0);
        _assertClaimAmountExercised(claimIds[1], 0);
        _assertClaimAmountExercised(claimIds[2], 0);
        _assertClaimAmountExercised(claimIds[3], 1);
        _assertClaimAmountExercised(claimIds[4], 0);
        _assertClaimAmountExercised(claimIds[5], 0);
        _assertClaimAmountExercised(claimIds[6], 0);

        // assigns a single option on day 4
        engine.exercise(optionId, 1);
        _assertClaimAmountExercised(claimIds[0], 0);
        _assertClaimAmountExercised(claimIds[1], 0);
        _assertClaimAmountExercised(claimIds[2], 0);
        _assertClaimAmountExercised(claimIds[3], 1);
        _assertClaimAmountExercised(claimIds[4], 1);
        _assertClaimAmountExercised(claimIds[5], 0);
        _assertClaimAmountExercised(claimIds[6], 0);

        // assigns a single option on day 1
        engine.exercise(optionId, 1);
        _assertClaimAmountExercised(claimIds[0], 0);
        _assertClaimAmountExercised(claimIds[1], 1);
        _assertClaimAmountExercised(claimIds[2], 0);
        _assertClaimAmountExercised(claimIds[3], 1);
        _assertClaimAmountExercised(claimIds[4], 1);
        _assertClaimAmountExercised(claimIds[5], 0);
        _assertClaimAmountExercised(claimIds[6], 0);
    }

    // **********************************************************************
    //                            PROTOCOL ADMIN
    // **********************************************************************

    function testSetFeeTo() public {
        // precondition check
        assertEq(engine.feeTo(), FEE_TO);

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0xCAFE));

        assertEq(engine.feeTo(), address(0xCAFE));
    }

    function testRevertSetFeeToWhenNotCurrentFeeTo() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.AccessControlViolation.selector, ALICE, FEE_TO));

        vm.prank(ALICE);
        engine.setFeeTo(address(0xCAFE));
    }

    function testRevertSetFeeToWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidFeeToAddress.selector, address(0)));

        vm.prank(FEE_TO);
        engine.setFeeTo(address(0));
    }

    // **********************************************************************
    //                            TOKEN ID ENCODING HELPERS
    // **********************************************************************

    function testEncodeTokenId() public {
        // Create new option type
        uint256 oTokenId =
            engine.newOptionType(DAI_A, 1, USDC_A, 100, uint40(block.timestamp), uint40(block.timestamp + 30 days));

        // Write 2 separate options lots
        vm.prank(ALICE);
        uint256 cTokenId1 = engine.write(oTokenId, 7);
        vm.prank(ALICE);
        uint256 cTokenId2 = engine.write(oTokenId, 3);

        // Check encoding the first claim
        (uint160 decodedOptionId,) = engine.decodeTokenId(cTokenId1);
        uint96 expectedClaimIndex1 = 1;
        assertEq(engine.encodeTokenId(decodedOptionId, expectedClaimIndex1), cTokenId1);

        // Check encoding the second claim
        uint96 expectedClaimIndex2 = 2;
        assertEq(engine.encodeTokenId(decodedOptionId, expectedClaimIndex2), cTokenId2);
    }

    function testFuzzEncodeTokenId(uint256 optionId, uint256 claimIndex) public {
        optionId = bound(optionId, 0, type(uint160).max);
        claimIndex = bound(claimIndex, 0, type(uint96).max);

        uint256 expectedTokenId = claimIndex;
        expectedTokenId |= optionId << 96;

        assertEq(engine.encodeTokenId(uint160(optionId), uint96(claimIndex)), expectedTokenId);
    }

    function testDecodeTokenId() public {
        // Create new option type
        uint256 oTokenId =
            engine.newOptionType(DAI_A, 1, USDC_A, 100, uint40(block.timestamp), uint40(block.timestamp + 30 days));

        // Write 2 separate options lots
        vm.prank(ALICE);
        uint256 cTokenId1 = engine.write(oTokenId, 7);
        vm.prank(ALICE);
        uint256 cTokenId2 = engine.write(oTokenId, 3);

        (uint160 decodedOptionIdFromOTokenId, uint96 decodedClaimIndexFromOTokenId) = engine.decodeTokenId(oTokenId);
        assertEq(decodedOptionIdFromOTokenId, oTokenId >> 96);
        assertEq(decodedClaimIndexFromOTokenId, 0); // no claims when initially creating a new option type

        (uint160 decodedOptionIdFromCTokenId1, uint96 decodedClaimIndexFromCTokenId1) = engine.decodeTokenId(cTokenId1);
        assertEq(decodedOptionIdFromCTokenId1, oTokenId >> 96);
        assertEq(decodedClaimIndexFromCTokenId1, 1); // first claim

        (uint160 decodedOptionIdFromCTokenId2, uint96 decodedClaimIndexFromCTokenId2) = engine.decodeTokenId(cTokenId2);
        assertEq(decodedOptionIdFromCTokenId2, oTokenId >> 96);
        assertEq(decodedClaimIndexFromCTokenId2, 2); // second claim
    }

    function testFuzzDecodeTokenId(uint256 optionId, uint256 claimId) public {
        optionId = bound(optionId, 0, type(uint160).max);
        claimId = bound(claimId, 0, type(uint96).max);

        uint256 testTokenId = claimId;
        testTokenId |= optionId << 96;

        (uint160 decodedOptionId, uint96 decodedClaimId) = engine.decodeTokenId(testTokenId);
        assertEq(decodedOptionId, optionId);
        assertEq(decodedClaimId, claimId);
    }

    function testGetOptionForTokenId() public {
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: DAI_A,
            underlyingAmount: 1,
            exerciseAsset: USDC_A,
            exerciseAmount: 100,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days),
            settlementSeed: 0,
            nextClaimNum: 0
        });
        uint256 optionId =
            engine.newOptionType(DAI_A, 1, USDC_A, 100, uint40(block.timestamp), uint40(block.timestamp + 30 days));

        // Update struct values to match stored option data structure
        uint160 optionKey = uint160(bytes20(keccak256(abi.encode(option))));

        option.settlementSeed = optionKey; // settlement seed is initially equal to option key
        option.nextClaimNum = 1; // next claim num has been incremented

        assertEq(engine.option(optionId), option);
    }

    function testGetClaimForTokenId() public {
        uint256 optionId =
            engine.newOptionType(DAI_A, 1, USDC_A, 100, uint40(block.timestamp), uint40(block.timestamp + 30 days));

        vm.prank(ALICE);
        uint256 claimId = engine.write(optionId, 7);

        IOptionSettlementEngine.OptionLotClaim memory claim = engine.claim(claimId);

        assertEq(claim.amountWritten, 7);
        assertEq(claim.claimed, false);
    }

    function testIsOptionInitialized() public {
        uint256 oTokenId =
            engine.newOptionType(DAI_A, 1, USDC_A, 100, uint40(block.timestamp), uint40(block.timestamp + 30 days));

        (uint160 decodedOptionId,) = engine.decodeTokenId(oTokenId);

        assertTrue(engine.isOptionInitialized(decodedOptionId));
        assertFalse(engine.isOptionInitialized(1337));
    }

    // **********************************************************************
    //                            EVENT TESTS
    // **********************************************************************

    function testEventNewOptionType() public {
        IOptionSettlementEngine.Option memory optionInfo = IOptionSettlementEngine.Option({
            underlyingAsset: DAI_A,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp,
            exerciseAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            settlementSeed: 0,
            exerciseAmount: testExerciseAmount,
            nextClaimNum: 1
        });

        uint256 expectedOptionId = _createOptionIdFromStruct(optionInfo);

        vm.expectEmit(false, true, true, true);
        emit NewOptionType(
            expectedOptionId,
            WETH_A,
            DAI_A,
            testExerciseAmount,
            testUnderlyingAmount,
            testExerciseTimestamp,
            testExpiryTimestamp,
            1
            );

        engine.newOptionType(
            DAI_A, testUnderlyingAmount, WETH_A, testExerciseAmount, testExerciseTimestamp, testExpiryTimestamp
        );
    }

    function testEventWriteWhenNewClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(WETH_A, ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, 0, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1);
    }

    function testEventWriteWhenExistingClaim() public {
        uint256 expectedFeeAccruedAmount = ((testUnderlyingAmount / 10_000) * engine.feeBps());

        vm.prank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(WETH_A, ALICE, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsWritten(testOptionId, ALICE, claimId, 1);

        vm.prank(ALICE);
        engine.write(testOptionId, 1, claimId);
    }

    function testEventExercise() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        engine.decodeTokenId(testOptionId);
        uint256 expectedFeeAccruedAmount = (testExerciseAmount / 10_000) * engine.feeBps();

        vm.expectEmit(true, true, true, true);
        emit FeeAccrued(DAI_A, BOB, expectedFeeAccruedAmount);

        vm.expectEmit(true, true, true, true);
        emit OptionsExercised(testOptionId, BOB, 1);

        vm.prank(BOB);
        engine.exercise(testOptionId, 1);
    }

    function testEventRedeem() public {
        vm.startPrank(ALICE);
        uint96 amountWritten = 7;
        uint256 claimId = engine.write(testOptionId, amountWritten);
        (uint256 optionId,) = engine.decodeTokenId(claimId);
        uint96 expectedUnderlyingAmount = testUnderlyingAmount * amountWritten;

        vm.warp(testExpiryTimestamp + 1 seconds);

        vm.expectEmit(true, true, true, true);
        emit ClaimRedeemed(
            claimId,
            optionId,
            ALICE,
            DAI_A,
            WETH_A,
            uint96(0), // no one has exercised
            uint96(expectedUnderlyingAmount)
            );

        engine.redeem(claimId);
    }

    function testEventSweepFeesWhenFeesAccruedForWrite() public {
        address[] memory tokens = new address[](3);
        tokens[0] = WETH_A;
        tokens[1] = DAI_A;
        tokens[2] = USDC_A;

        uint96 daiUnderlyingAmount = 9 * 10 ** 18;
        uint96 usdcUnderlyingAmount = 7 * 10 ** 9; // not 18 decimals

        // Write option that will generate WETH fees
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        // Write option that will generate DAI fees
        (uint256 daiOptionId,) = _createNewOptionType({
            underlyingAsset: DAI_A,
            underlyingAmount: daiUnderlyingAmount,
            exerciseAsset: WETH_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(daiOptionId, 1);

        // Write option that will generate USDC fees
        (uint256 usdcOptionId,) = _createNewOptionType({
            underlyingAsset: USDC_A,
            underlyingAmount: usdcUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcOptionId, 1);
        vm.stopPrank();

        // Then assert expected fee amounts
        uint256[] memory expectedFees = new uint256[](3);
        expectedFees[0] = ((testUnderlyingAmount / 10_000) * engine.feeBps());
        expectedFees[1] = ((daiUnderlyingAmount / 10_000) * engine.feeBps());
        expectedFees[2] = ((usdcUnderlyingAmount / 10_000) * engine.feeBps());

        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i] - 1); // sweeps 1 wei less as gas optimization
        }

        // When fees are swept
        engine.sweepFees(tokens);
    }

    function testEventSweepFeesWhenFeesAccruedForExercise() public {
        address[] memory tokens = new address[](3);
        tokens[0] = DAI_A;
        tokens[1] = WETH_A;
        tokens[2] = USDC_A;

        uint96 daiExerciseAmount = 9 * 10 ** 18;
        uint96 wethExerciseAmount = 3 * 10 ** 18;
        uint96 usdcExerciseAmount = 7 * 10 ** 9; // not 18 decimals

        // Write option for WETH-DAI pair
        vm.startPrank(ALICE);
        (uint256 daiExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: daiExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(daiExerciseOptionId, 1);

        // Write option for DAI-WETH pair
        (uint256 wethExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: DAI_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: WETH_A,
            exerciseAmount: wethExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(wethExerciseOptionId, 1);

        // Write option for DAI-USDC pair
        (uint256 usdcExerciseOptionId,) = _createNewOptionType({
            underlyingAsset: DAI_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: USDC_A,
            exerciseAmount: usdcExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
        engine.write(usdcExerciseOptionId, 1);

        // Transfer all option contracts to Bob
        engine.safeTransferFrom(ALICE, BOB, daiExerciseOptionId, 1, "");
        engine.safeTransferFrom(ALICE, BOB, wethExerciseOptionId, 1, "");
        engine.safeTransferFrom(ALICE, BOB, usdcExerciseOptionId, 1, "");
        vm.stopPrank();

        vm.warp(testExpiryTimestamp - 1 seconds);

        // Clear away fees generated by writing options
        engine.sweepFees(tokens);

        // Exercise option that will generate WETH fees
        vm.startPrank(BOB);
        engine.exercise(daiExerciseOptionId, 1);

        // Exercise option that will generate DAI fees
        engine.exercise(wethExerciseOptionId, 1);

        // Exercise option that will generate USDC fees
        engine.exercise(usdcExerciseOptionId, 1);
        vm.stopPrank();

        // Then assert expected fee amounts
        uint256[] memory expectedFees = new uint256[](3);
        expectedFees[0] = ((daiExerciseAmount / 10_000) * engine.feeBps());
        expectedFees[1] = ((wethExerciseAmount / 10_000) * engine.feeBps());
        expectedFees[2] = ((usdcExerciseAmount / 10_000) * engine.feeBps());

        for (uint256 i = 0; i < tokens.length; i++) {
            vm.expectEmit(true, true, true, false);
            emit FeeSwept(tokens[i], engine.feeTo(), expectedFees[i]); // sweeps 1 wei less as gas optimization
        }

        // When fees are swept
        engine.sweepFees(tokens);
    }

    // **********************************************************************
    //                            FAIL TESTS
    // **********************************************************************

    function testRevertNewOptionTypeWhenOptionsTypeExists() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.OptionsTypeExists.selector, testOptionId));
        _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevertNewOptionTypeWhenExpiryTooSoon() public {
        uint40 tooSoonExpiryTimestamp = uint40(block.timestamp + 1 days - 1 seconds);
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: DAI_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: WETH_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: tooSoonExpiryTimestamp,
            settlementSeed: 0, // default zero for settlement seed
            nextClaimNum: 0 // default zero for next claim id
        });
        _createOptionIdFromStruct(option);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiryWindowTooShort.selector, testExpiryTimestamp - 1)
        );
        engine.newOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp - 1
        });
    }

    function testRevertNewOptionTypeWhenExerciseWindowTooShort() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExerciseWindowTooShort.selector, uint40(block.timestamp + 1))
        );
        engine.newOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: uint40(block.timestamp + 1),
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevertNewOptionTypeWhenInvalidAssets() public {
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, DAI_A, DAI_A));
        _createNewOptionType({
            underlyingAsset: DAI_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevertNewOptionTypeWhenTotalSuppliesAreTooLowToExercise() public {
        uint96 underlyingAmountExceedsTotalSupply = uint96(IERC20(DAI_A).totalSupply() + 1);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, DAI_A, WETH_A));

        _createNewOptionType({
            underlyingAsset: DAI_A,
            underlyingAmount: underlyingAmountExceedsTotalSupply,
            exerciseAsset: WETH_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });

        uint96 exerciseAmountExceedsTotalSupply = uint96(IERC20(USDC_A).totalSupply() + 1);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidAssets.selector, USDC_A, WETH_A));

        _createNewOptionType({
            underlyingAsset: USDC_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: WETH_A,
            exerciseAmount: exerciseAmountExceedsTotalSupply,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp
        });
    }

    function testRevertWriteWhenInvalidOption() public {
        // Option ID not 0 in lower 96 b
        uint256 invalidOptionId = testOptionId + 1;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));
        engine.write(invalidOptionId, 1);

        // Option ID not initialized
        invalidOptionId = testOptionId / 2;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));
        engine.write(invalidOptionId, 1);
    }

    function testRevertWriteWhenEncodedOptionIdInClaimIdDoesNotMatchProvidedOptionId() public {
        uint256 option1Claim1 = engine.encodeTokenId(0xDEADBEEF1, 0xCAFECAFE1);
        uint256 option2WithoutClaim = engine.encodeTokenId(0xDEADBEEF2, 0x0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOptionSettlementEngine.EncodedOptionIdInClaimIdDoesNotMatchProvidedOptionId.selector,
                option1Claim1,
                option2WithoutClaim
            )
        );

        engine.write(option2WithoutClaim, 1, option1Claim1);
    }

    function testRevertWriteWhenAmountWrittenCannotBeZero() public {
        uint112 invalidWriteAmount = 0;

        vm.expectRevert(IOptionSettlementEngine.AmountWrittenCannotBeZero.selector);

        engine.write(testOptionId, invalidWriteAmount);
    }

    function testRevertWriteExpiredOption() public {
        vm.warp(testExpiryTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        engine.write(testOptionId, 1);
    }

    function testRevertExerciseBeforeExcercise() public {
        _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseTimestamp + 1,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: testExpiryTimestamp + 1
        });

        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        vm.stopPrank();
    }

    function testRevertWriteWhenCallerDoesNotOwnClaimId() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(BOB);
        engine.write(testOptionId, 1, claimId);
    }

    function testRevertWriteWhenExpiredOption() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExpiryTimestamp + 1 seconds);

        engine.redeem(claimId);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );

        engine.write(testOptionId, 1, claimId);
        vm.stopPrank();
    }

    function testRevertExerciseWhenExerciseTooEarly() public {
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Bob immediately exercises before exerciseTimestamp
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOptionSettlementEngine.ExerciseTooEarly.selector, testOptionId, testExerciseTimestamp
            )
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevertExerciseWhenInvalidOption() public {
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);

        uint256 invalidOptionId = testOptionId + 1;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidOption.selector, invalidOptionId));

        engine.exercise(invalidOptionId, 1);
    }

    function testRevertExerciseWhenExpiredOption() public {
        uint256 ts = block.timestamp;
        // ====== Exercise at Expiry =======
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();

        vm.warp(ts);
        // ====== Exercise after Expiry =======
        // Alice writes
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, testOptionId, 1, "");
        vm.stopPrank();

        // Fast-forward to at expiry
        vm.warp(testExpiryTimestamp + 1 seconds);

        // Bob exercises
        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ExpiredOption.selector, testOptionId, testExpiryTimestamp)
        );
        engine.exercise(testOptionId, 1);
        vm.stopPrank();
    }

    function testRevertRedeemWhenInvalidClaim() public {
        uint256 badClaimId = engine.encodeTokenId(0xDEADBEEF, 0);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.InvalidClaim.selector, badClaimId));

        vm.prank(ALICE);
        engine.redeem(badClaimId);
    }

    function testRevertExerciseWhenCallerHoldsInsufficientOptions() public {
        vm.warp(testExerciseTimestamp + 1 seconds);

        // Should revert if you hold 0
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.CallerHoldsInsufficientOptions.selector, testOptionId, 1)
        );
        engine.exercise(testOptionId, 1);

        // Should revert if you hold some, but not enough
        vm.startPrank(ALICE);
        engine.write(testOptionId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.CallerHoldsInsufficientOptions.selector, testOptionId, 2)
        );
        engine.exercise(testOptionId, 2);
    }

    function testRevertRedeemWhenCallerDoesNotOwnClaimId() public {
        // Alice writes and transfers to Bob, then Alice tries to redeem
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);
        engine.safeTransferFrom(ALICE, BOB, claimId, 1, "");

        vm.warp(testExpiryTimestamp);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        engine.redeem(claimId);
        vm.stopPrank();

        // Carol feels left out and tries to redeem what she can't
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        vm.prank(CAROL);
        engine.redeem(claimId);

        // Bob redeems, which burns the Claim NFT, and then is unable to redeem a second time
        vm.startPrank(BOB);
        engine.redeem(claimId);

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.CallerDoesNotOwnClaimId.selector, claimId));

        engine.redeem(claimId);
        vm.stopPrank();
    }

    function testRevertRedeemWhenClaimTooSoon() public {
        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, 1);

        vm.warp(testExerciseTimestamp - 1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOptionSettlementEngine.ClaimTooSoon.selector, claimId, testExpiryTimestamp)
        );

        engine.redeem(claimId);
    }

    function testRevertUnderlyingWhenTokenNotFound() public {
        uint256 badOptionId = 123;

        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, badOptionId));

        engine.underlying(badOptionId);
    }

    function testRevertUriWhenTokenNotFound() public {
        uint256 tokenId = 420;
        vm.expectRevert(abi.encodeWithSelector(IOptionSettlementEngine.TokenNotFound.selector, tokenId));
        engine.uri(420);
    }

    // **********************************************************************
    //                            FUZZ TESTS
    // **********************************************************************

    function testFuzzNewOptionType(
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
        vm.assume(underlyingAmount <= WETH.totalSupply());
        vm.assume(exerciseAmount <= DAI.totalSupply());

        (uint256 optionId, IOptionSettlementEngine.Option memory optionInfo) = _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: underlyingAmount,
            exerciseAsset: DAI_A,
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
        assertEq(optionRecord.underlyingAsset, WETH_A);
        assertEq(optionRecord.exerciseAsset, DAI_A);
        assertEq(optionRecord.exerciseTimestamp, exerciseTimestamp);
        assertEq(optionRecord.expiryTimestamp, expiryTimestamp);
        assertEq(optionRecord.underlyingAmount, underlyingAmount);
        assertEq(optionRecord.exerciseAmount, exerciseAmount);

        _assertTokenIsOption(optionId);
    }

    function testFuzzWrite(uint112 amount) public {
        uint256 wethBalanceEngine = WETH.balanceOf(address(engine));
        uint256 wethBalance = WETH.balanceOf(ALICE);

        vm.assume(amount > 0);
        vm.assume(amount <= wethBalance / testUnderlyingAmount);

        uint256 rxAmount = amount * testUnderlyingAmount;
        uint256 fee = ((rxAmount / 10000) * engine.feeBps());

        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, amount);
        IOptionSettlementEngine.OptionLotClaim memory claimRecord = engine.claim(claimId);

        assertEq(WETH.balanceOf(address(engine)), wethBalanceEngine + rxAmount + fee);
        assertEq(WETH.balanceOf(ALICE), wethBalance - rxAmount - fee);

        assertEq(engine.balanceOf(ALICE, testOptionId), amount);
        assertEq(engine.balanceOf(ALICE, claimId), 1);
        assertTrue(!claimRecord.claimed);

        (uint160 optionId, uint96 claimIdx) = engine.decodeTokenId(claimId);
        assertEq(uint256(optionId) << 96, testOptionId);
        assertEq(claimIdx, 1);
        assertEq(claimRecord.amountWritten, amount);
        _assertClaimAmountExercised(claimId, 0);

        _assertTokenIsClaim(claimId);
    }

    function testFuzzExercise(uint112 amountWrite, uint112 amountExercise) public {
        uint256 wethBalanceEngine = WETH.balanceOf(address(engine));
        uint256 daiBalanceEngine = DAI.balanceOf(address(engine));
        uint256 wethBalance = WETH.balanceOf(ALICE);
        uint256 daiBalance = DAI.balanceOf(ALICE);

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

        IOptionSettlementEngine.OptionLotClaim memory claimRecord = engine.claim(claimId);

        assertTrue(!claimRecord.claimed);
        assertEq(claimRecord.amountWritten, amountWrite);
        _assertClaimAmountExercised(claimId, amountExercise);

        assertEq(WETH.balanceOf(address(engine)), wethBalanceEngine + writeAmount - txAmount + writeFee);
        assertEq(WETH.balanceOf(ALICE), (wethBalance - writeAmount + txAmount - writeFee));
        assertEq(DAI.balanceOf(address(engine)), daiBalanceEngine + rxAmount + exerciseFee);
        assertEq(DAI.balanceOf(ALICE), (daiBalance - rxAmount - exerciseFee));
        assertEq(engine.balanceOf(ALICE, testOptionId), amountWrite - amountExercise);
        assertEq(engine.balanceOf(ALICE, claimId), 1);
    }

    function testFuzzRedeem(uint112 amountWrite, uint112 amountExercise) public {
        uint256 wethBalanceEngine = WETH.balanceOf(address(engine));
        uint256 daiBalanceEngine = DAI.balanceOf(address(engine));
        uint256 wethBalance = WETH.balanceOf(ALICE);
        uint256 daiBalance = DAI.balanceOf(ALICE);

        vm.assume(amountWrite > 0);
        vm.assume(amountExercise > 0);
        vm.assume(amountWrite >= amountExercise);
        vm.assume(amountWrite <= wethBalance / testUnderlyingAmount);
        vm.assume(amountExercise <= daiBalance / testExerciseAmount);

        uint256 rxAmount = amountExercise * testExerciseAmount;
        uint256 exerciseFee = (rxAmount / 10000) * engine.feeBps();
        uint256 writeFee = ((amountWrite * testUnderlyingAmount) / 10000) * engine.feeBps();

        vm.startPrank(ALICE);
        uint256 claimId = engine.write(testOptionId, amountWrite);

        vm.warp(testExpiryTimestamp - 1);
        engine.exercise(testOptionId, amountExercise);

        vm.warp(1e15);

        engine.redeem(claimId);

        IOptionSettlementEngine.OptionLotClaim memory claimRecord = engine.claim(claimId);

        assertEq(WETH.balanceOf(address(engine)), wethBalanceEngine + writeFee);
        assertEq(WETH.balanceOf(ALICE), wethBalance - writeFee);
        assertEq(DAI.balanceOf(address(engine)), daiBalanceEngine + exerciseFee);
        assertEq(DAI.balanceOf(ALICE), daiBalance - exerciseFee);
        assertEq(engine.balanceOf(ALICE, testOptionId), amountWrite - amountExercise);
        assertEq(engine.balanceOf(ALICE, claimId), 0);
        assertTrue(claimRecord.claimed);

        _assertTokenIsClaim(claimId);
    }

    struct FuzzMetadata {
        uint256 claimsLength;
        uint256 totalWritten;
        uint256 totalExercised;
    }

    function testFuzzWriteExerciseRedeem(uint32 seed) public {
        uint32 i = 0;
        uint256[] memory claimIds1 = new uint256[](30);
        FuzzMetadata memory opt1 = FuzzMetadata(0, 0, 0);
        uint256[] memory claimIds2 = new uint256[](90);
        FuzzMetadata memory opt2 = FuzzMetadata(0, 0, 0);

        // create monthly option
        (uint256 optionId1M, IOptionSettlementEngine.Option memory option1M) = _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
            exerciseAmount: testExerciseAmount,
            exerciseTimestamp: testExerciseTimestamp,
            expiryTimestamp: uint40(block.timestamp + 30 days)
        });

        // create quarterly option
        (uint256 optionId3M, IOptionSettlementEngine.Option memory option3M) = _createNewOptionType({
            underlyingAsset: WETH_A,
            underlyingAmount: testUnderlyingAmount,
            exerciseAsset: DAI_A,
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
        IOptionSettlementEngine.Underlying memory underlying = engine.underlying(claimId);
        uint256 exerciseAssetAmount = ERC20(underlying.exerciseAsset).balanceOf(claimant);
        uint256 underlyingAssetAmount = ERC20(underlying.underlyingAsset).balanceOf(claimant);
        engine.redeem(claimId);

        assertEq(
            ERC20(underlying.underlyingAsset).balanceOf(claimant),
            underlyingAssetAmount + uint256(underlying.underlyingPosition)
        );
        assertEq(
            ERC20(underlying.exerciseAsset).balanceOf(claimant),
            exerciseAssetAmount + uint256(underlying.exercisePosition)
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
                    engine.write(optionId, toWrite, claimId);
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

    // **********************************************************************
    //                            TEST HELPERS
    // **********************************************************************

    function _assertTokenIsClaim(uint256 tokenId) internal {
        if (engine.tokenType(tokenId) != IOptionSettlementEngine.Type.OptionLotClaim) {
            assertTrue(false);
        }
    }

    function _assertTokenIsOption(uint256 tokenId) internal {
        if (engine.tokenType(tokenId) == IOptionSettlementEngine.Type.OptionLotClaim) {
            assertTrue(false);
        }
    }

    function _assertPosition(int256 actual, uint96 expected) internal {
        uint96 _actual = uint96(int96(actual));
        assertEq(_actual, expected);
    }

    function _assertClaimAmountExercised(uint256 claimId, uint112 amount) internal {
        IOptionSettlementEngine.Underlying memory underlying = engine.underlying(claimId);
        IOptionSettlementEngine.Option memory option = engine.option(claimId);
        uint112 amountExercised = uint112(uint256(underlying.exercisePosition) / option.exerciseAmount);
        assertEq(amount, amountExercised);
    }

    function _writeAndExerciseNewOption(
        address underlyingAsset,
        uint96 underlyingAmount,
        address exerciseAsset,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp,
        address writer,
        address exerciser
    ) internal returns (uint256 optionId, uint256 claimId) {
        (optionId,) = _createNewOptionType({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp
        });
        claimId = _writeAndExerciseOption(optionId, writer, exerciser);
    }

    function _createNewOptionType(
        address underlyingAsset,
        uint96 underlyingAmount,
        address exerciseAsset,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) internal returns (uint256 optionId, IOptionSettlementEngine.Option memory option) {
        (, option) = _getNewOptionType({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp
        });
        optionId = engine.newOptionType({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp
        });
    }

    function _getNewOptionType(
        address underlyingAsset,
        uint96 underlyingAmount,
        address exerciseAsset,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) internal pure returns (uint256 optionId, IOptionSettlementEngine.Option memory option) {
        option = IOptionSettlementEngine.Option({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp,
            settlementSeed: 0, // default zero for settlement seed
            nextClaimNum: 0 // default zero for next claim id
        });
        optionId = _createOptionIdFromStruct(option);
    }

    function _writeAndExerciseOption(uint256 optionId, address writer, address exerciser)
        internal
        returns (uint256 claimId)
    {
        claimId = _writeAndExerciseOption(optionId, writer, exerciser, 1, 1);
    }

    function _writeAndExerciseOption(
        uint256 optionId,
        address writer,
        address exerciser,
        uint112 toWrite,
        uint112 toExercise
    ) internal returns (uint256 claimId) {
        if (toWrite > 0) {
            vm.startPrank(writer);
            claimId = engine.write(optionId, toWrite);
            engine.safeTransferFrom(writer, exerciser, optionId, toWrite, "");
            vm.stopPrank();
        }

        if (toExercise > 0) {
            vm.warp(testExerciseTimestamp + 1);
            vm.startPrank(exerciser);
            engine.exercise(optionId, toExercise);
            vm.stopPrank();
        }
    }

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    function _getDaysBucket() internal view returns (uint16) {
        return uint16(block.timestamp / 1 days);
    }

    function _getDaysFromBucket(uint256 ts, uint16 daysFrom) internal pure returns (uint16) {
        return uint16((ts + daysFrom * 1 days) / 1 days);
    }

    /// @dev probability in bips
    function _coinflip(uint32 seed, uint16 probability) internal pure returns (bool) {
        return _randBetween(seed, 10000) < probability;
    }

    function _randBetween(uint32 seed, uint256 max) internal pure returns (uint256) {
        uint256 h = uint256(keccak256(abi.encode(seed)));
        return h % max;
    }

    function _createOptionIdFromStruct(IOptionSettlementEngine.Option memory optionInfo)
        internal
        pure
        returns (uint256)
    {
        uint160 optionKey = uint160(bytes20(keccak256(abi.encode(optionInfo))));

        return uint256(optionKey) << 96;
    }

    function assertEq(IOptionSettlementEngine.Option memory actual, IOptionSettlementEngine.Option memory expected)
        public
    {
        assertEq(actual.underlyingAsset, expected.underlyingAsset);
        assertEq(actual.underlyingAmount, expected.underlyingAmount);
        assertEq(actual.exerciseAsset, expected.exerciseAsset);
        assertEq(actual.exerciseAmount, expected.exerciseAmount);
        assertEq(actual.exerciseTimestamp, expected.exerciseTimestamp);
        assertEq(actual.expiryTimestamp, expected.expiryTimestamp);
        assertEq(actual.settlementSeed, expected.settlementSeed);
        assertEq(actual.nextClaimNum, expected.nextClaimNum);
    }

    event FeeSwept(address indexed token, address indexed feeTo, uint256 amount);

    event NewOptionType(
        uint256 indexed optionId,
        address indexed exerciseAsset,
        address indexed underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp,
        uint96 nextClaimNum
    );

    event OptionsExercised(uint256 indexed optionId, address indexed exercisee, uint112 amount);

    event OptionsWritten(uint256 indexed optionId, address indexed writer, uint256 indexed claimId, uint112 amount);

    event FeeAccrued(address indexed asset, address indexed payor, uint256 amount);

    event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        address exerciseAsset,
        address underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount
    );
}
