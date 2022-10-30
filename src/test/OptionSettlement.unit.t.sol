// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "forge-std/Test.sol";
import "./MockERC20.sol";
import "./interfaces/IERC20.sol";
import "../OptionSettlement.sol";

abstract contract ERC1155Receiver {
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

contract OptionSettlementttTest is Test, ERC1155Receiver {
    //

    OptionSettlementEngine internal engine;

    // Tokens
    IERC20 internal aToken;
    IERC20 internal bToken;
    address internal aTokenAddress;
    address internal bTokenAddress;

    // Users
    address internal constant ALICE = address(0xA);
    address internal constant BOB = address(0xB);
    address internal constant CAROL = address(0xC);

    // Option Contract
    uint256 internal optionId;
    uint256 internal constant duration1 = 1 days;
    uint256 internal constant duration2 = 30 days;
    uint256 internal constant duration3 = 90 days;

    function setUp() public {
        // Deploy OptionSettlementEngine
        engine = new OptionSettlementEngine();

        // Setup mock ERC20 tokens
        MockERC20 a = new MockERC20("Token A", "TKNA", 18);
        MockERC20 b = new MockERC20("Token B", "TKNB", 18);
        aTokenAddress = address(a);
        bTokenAddress = address(b);
        aToken = IERC20(aTokenAddress);
        bToken = IERC20(bTokenAddress);

        // Setup balances and approvals
        a.mint(ALICE, 100 * 10 ** 18);
        b.mint(ALICE, 100 * 10 ** 18);
        a.mint(BOB, 100 * 10 ** 18);
        b.mint(BOB, 100 * 10 ** 18);
        b.mint(CAROL, 100 * 10 ** 18);
        a.mint(CAROL, 100 * 10 ** 18);
        vm.startPrank(ALICE);
        a.approve(address(engine), type(uint256).max);
        b.approve(address(engine), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(BOB);
        a.approve(address(engine), type(uint256).max);
        b.approve(address(engine), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(CAROL);
        a.approve(address(engine), type(uint256).max);
        b.approve(address(engine), type(uint256).max);
        vm.stopPrank();
        engine.setApprovalForAll(address(this), true);

        // Setup test option contract
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: aTokenAddress,
            exerciseTimestamp: uint40(block.timestamp + duration1),
            expiryTimestamp: uint40(block.timestamp + duration1 + duration2),
            exerciseAsset: bTokenAddress,
            underlyingAmount: 1 * 10 ** 18,
            settlementSeed: 123_456_78,
            exerciseAmount: 2 * 10 ** 18,
            nextClaimId: 0
        });
        optionId = engine.newOptionType(option);
        // engine.newOptionTypeOther({
        //     _underlyingAsset: aTokenAddress,
        //     _exerciseTimestamp: uint40(block.timestamp + duration1),
        //     _expiryTimestamp: uint40(block.timestamp + duration2),
        //     _exerciseAsset: bTokenAddress,
        //     _underlyingAmount: 1 * 10 ** 18,
        //     _settlementSeed: 123_456_789,
        //     _exerciseAmount: 2 * 10 ** 18
        // });
    }

    // **********************************************************************
    //                            ENCODING / DECODING
    // **********************************************************************

    // MSb
    // 0000 0000   0000 0000   0000 0000   0000 0000 ┐
    // 0000 0000   0000 0000   0000 0000   0000 0000 │ 
    // 0000 0000   0000 0000   0000 0000   0000 0000 │ 160b hash of option data structure
    // 0000 0000   0000 0000   0000 0000   0000 0000 │
    // 0000 0000   0000 0000   0000 0000   0000 0000 │
    // 0000 0000   0000 0000   0000 0000   0000 0000 ┘
    // 0000 0000   0000 0000   0000 0000   0000 0000 ┐
    // 0000 0000   0000 0000   0000 0000   0000 0000 │ 96b encoding of claim ID
    // 0000 0000   0000 0000   0000 0000   0000 0000 ┘
    //                                           LSb

    // function testGetDecodedIdComponents() public {
        
    // }

    // 73882001658513674273974860507440572138319254363977631541755946729899483463680

    function test_GetDecodedIdComponents() public {
        IOptionSettlementEngine.Option memory option = IOptionSettlementEngine.Option({
            underlyingAsset: bTokenAddress,
            underlyingAmount: 1,
            exerciseAsset: aTokenAddress,
            exerciseAmount: 100,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: uint40(block.timestamp + 30 days),
            settlementSeed: 0,
            nextClaimId: 0
        });

        uint256 oTokenId = engine.newOptionType(option);
        emit log_named_uint("Token ID for new Option type", oTokenId);

        vm.prank(ALICE);
        uint256 cTokenId1 = engine.write(oTokenId, 1);
        emit log_named_uint("Token ID for Claim for Option type 1 written 1", cTokenId1);

        vm.prank(ALICE);
        uint256 cTokenId2 = engine.write(oTokenId, 1);
        emit log_named_uint("Token ID for Claim for Option type 1 written 2", cTokenId2);

        (uint160 decodedOptionId, uint96 decodedClaimId) = engine.getDecodedIdComponents(oTokenId);
        // 932521963326006281865975323499229523960747548255
        // or, 7.388200166e76 when << 96 =)
        emit log_named_uint("Decoded Option ID", decodedOptionId);
        // 0, or 1, or 2
        emit log_named_uint("Decoded Claim ID ", decodedClaimId);

        (, uint96 decodedClaimIdForFirstWrittenOption) = engine.getDecodedIdComponents(cTokenId1);
        assertEq(decodedClaimIdForFirstWrittenOption, 1);
        (, uint96 decodedClaimIdForSecondWrittenOption) = engine.getDecodedIdComponents(cTokenId2);
        assertEq(decodedClaimIdForSecondWrittenOption, 2);
    }

    // **********************************************************************
    //                            EXERCISE
    // **********************************************************************

    function test_Exercise() public {
        uint256 aTokenBalanceEngine = aToken.balanceOf(address(engine));
        uint256 aTokenBalanceAlice = aToken.balanceOf(ALICE);
        uint256 aTokenBalanceBob = aToken.balanceOf(BOB);
        uint256 bTokenBalanceEngine = bToken.balanceOf(address(engine));
        uint256 bTokenBalanceAlice = bToken.balanceOf(ALICE);
        uint256 bTokenBalanceBob = bToken.balanceOf(BOB);

        vm.startPrank(ALICE);
        engine.write(optionId, 1);
        engine.safeTransferFrom(ALICE, BOB, optionId, 1, "");
        vm.stopPrank();

        assertEq(engine.balanceOf(ALICE, optionId), 0);
        assertEq(engine.balanceOf(BOB, optionId), 1);

        uint256 writeAmount = 1 * 1 * 10 ** 18;
        uint256 writeFee = (writeAmount / 10_000) * engine.feeBps();

        uint256 exerciseAmount = 1 * 2 * 10 ** 18;
        uint256 exerciseFee = (exerciseAmount / 10_000) * engine.feeBps();

        assertEq(aToken.balanceOf(address(engine)), aTokenBalanceEngine + writeAmount + writeFee);

        vm.warp(block.timestamp + duration1 + duration2 - 1 seconds);

        vm.prank(BOB);
        engine.exercise(optionId, 1);

        assertEq(engine.balanceOf(BOB, optionId), 0);

        assertEq(aToken.balanceOf(address(engine)), aTokenBalanceEngine + writeFee);
        assertEq(aToken.balanceOf(ALICE), aTokenBalanceAlice - writeAmount - writeFee);
        assertEq(aToken.balanceOf(BOB), aTokenBalanceBob + writeAmount);
        assertEq(bToken.balanceOf(address(engine)), bTokenBalanceEngine + exerciseAmount + exerciseFee);
        assertEq(bToken.balanceOf(ALICE), bTokenBalanceAlice);
        assertEq(bToken.balanceOf(BOB), bTokenBalanceBob - exerciseAmount - exerciseFee);

        // TODO continue
    }
}
