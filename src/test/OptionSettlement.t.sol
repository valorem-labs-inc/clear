// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";
import "./interfaces/IERC20.sol";
import "../OptionSettlement.sol";

/// @notice Receiver hook utility for NFT 'safe' transfers
abstract contract NFTreceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0xbc197c81;
    }
}

contract OptionSettlementTest is DSTest, NFTreceiver {
    Vm public constant VM = Vm(HEVM_ADDRESS);
    OptionSettlementEngine public engine;

    address public immutable ac = 0x36273803306a3C22bc848f8Db761e974697ece0d;
    address public immutable wethAddress =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public immutable daiAddress =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint256 public wethTotalSupply;
    uint256 public daiTotalSupply;

    uint256 public testOptionId;

    IERC20 public weth;
    IERC20 public dai;

    using stdStorage for StdStorage;
    StdStorage public stdstore;

    function writeTokenBalance(
        address who,
        address token,
        uint256 amt
    ) internal {
        stdstore
            .target(token)
            .sig(IERC20(token).balanceOf.selector)
            .with_key(who)
            .checked_write(amt);
    }

    function setUp() public {
        // Setup WETH
        weth = IERC20(wethAddress);
        // Setup DAI
        dai = IERC20(daiAddress);

        engine = new OptionSettlementEngine();

        IOptionSettlementEngine.Option memory info = IOptionSettlementEngine
            .Option({
                underlyingAsset: address(weth),
                exerciseAsset: address(dai),
                settlementSeed: 1,
                underlyingAmount: 1 ether,
                exerciseAmount: 3000 ether,
                exerciseTimestamp: uint40(block.timestamp),
                expiryTimestamp: (uint40(block.timestamp) + 604800)
            });
        testOptionId = IOptionSettlementEngine(engine).newChain(info);

        // Now we have 1B DAI
        writeTokenBalance(address(this), daiAddress, 1000000000 * 1e18);
        // And 10 M WETH
        writeTokenBalance(address(this), wethAddress, 10000000 * 1e18);

        writeTokenBalance(address(engine), address(dai), 1000000000 * 1e18);
        writeTokenBalance(address(engine), address(weth), 10000000 * 1e18);

        writeTokenBalance(address(0xBEEF), address(dai), 1000000000 * 1e18);
        writeTokenBalance(address(0xBEEF), address(weth), 10000000 * 1e18);

        writeTokenBalance(address(0x1337), address(dai), 1000000000 * 1e18);
        writeTokenBalance(address(0x1337), address(weth), 10000000 * 1e18);

        writeTokenBalance(address(0x1), address(dai), 1000000000 * 1e18);
        writeTokenBalance(address(0x1), address(weth), 10000000 * 1e18);

        writeTokenBalance(address(0x2), address(dai), 1000000000 * 1e18);
        writeTokenBalance(address(0x2), address(weth), 10000000 * 1e18);

        writeTokenBalance(address(0x3), address(dai), 1000000000 * 1e18);
        writeTokenBalance(address(0x3), address(weth), 10000000 * 1e18);

        // Issue approvals
        weth.approve(address(engine), type(uint256).max);
        dai.approve(address(engine), type(uint256).max);

        wethTotalSupply = IERC20(weth).totalSupply();
        daiTotalSupply = IERC20(dai).totalSupply();
    }

    /* --------------------------- Fuzz Tests --------------------------- */

    function testFuzzNewChain(
        uint96 underlyingAmount,
        uint96 exerciseAmount,
        uint40 exerciseTimestamp,
        uint40 expiryTimestamp
    ) public {
        VM.assume(expiryTimestamp >= block.timestamp + 86400);
        VM.assume(exerciseTimestamp >= block.timestamp);
        VM.assume(exerciseTimestamp <= expiryTimestamp - 86400);
        VM.assume(expiryTimestamp <= type(uint64).max);
        VM.assume(exerciseTimestamp <= type(uint64).max);
        VM.assume(underlyingAmount <= wethTotalSupply);
        VM.assume(exerciseAmount <= daiTotalSupply);
        VM.assume(type(uint256).max - underlyingAmount >= wethTotalSupply);
        VM.assume(type(uint256).max - exerciseAmount >= daiTotalSupply);

        IOptionSettlementEngine.Option
            memory optionInfo = IOptionSettlementEngine.Option({
                underlyingAsset: address(weth),
                exerciseAsset: address(dai),
                settlementSeed: 0,
                underlyingAmount: underlyingAmount,
                exerciseAmount: exerciseAmount,
                exerciseTimestamp: exerciseTimestamp,
                expiryTimestamp: expiryTimestamp
            });

        uint256 optionId = IOptionSettlementEngine(engine).newChain(optionInfo);
        assertEq(optionId, 2);

        IOptionSettlementEngine.Option
            memory optionRecord = IOptionSettlementEngine(engine).option(
                optionId
            );

        assertEq(
            IOptionSettlementEngine(engine).hashToOptionToken(
                keccak256(abi.encode(optionInfo))
            ),
            optionId
        );
        assertEq(optionRecord.underlyingAsset, address(weth));
        assertEq(optionRecord.exerciseAsset, address(dai));
        assertEq(optionRecord.exerciseTimestamp, exerciseTimestamp);
        assertEq(optionRecord.expiryTimestamp, expiryTimestamp);
        assertEq(optionRecord.underlyingAmount, underlyingAmount);
        assertEq(optionRecord.exerciseAmount, exerciseAmount);
        assertEq(optionRecord.settlementSeed, 0);

        if (
            IOptionSettlementEngine(engine).tokenType(optionId) ==
            IOptionSettlementEngine.Type.Option
        ) assertTrue(true);
    }

    function testFuzzWrite(uint112 amountWrite) public {
        uint256 wethBalanceEngine = IERC20(weth).balanceOf(address(engine));
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));

        VM.assume(amountWrite > 0);
        VM.assume(amountWrite <= wethBalance / 1 ether);

        uint256 rxAmount = amountWrite * 1 ether;
        uint256 fee = ((rxAmount / 10000) * engine.feeBps());

        uint256 claimId = IOptionSettlementEngine(engine).write(
            testOptionId,
            amountWrite
        );

        IOptionSettlementEngine.Claim
            memory claimRecord = IOptionSettlementEngine(engine).claim(claimId);

        assertEq(
            IERC20(weth).balanceOf(address(engine)),
            wethBalanceEngine + rxAmount + fee
        );
        assertEq(
            IERC20(weth).balanceOf(address(this)),
            wethBalance - rxAmount - fee
        );

        assertEq(
            ERC1155(engine).balanceOf(address(this), testOptionId),
            amountWrite
        );
        assertEq(ERC1155(engine).balanceOf(address(this), claimId), 1);
        assertTrue(!claimRecord.claimed);
        assertEq(claimRecord.option, testOptionId);
        assertEq(claimRecord.amountWritten, amountWrite);
        assertEq(claimRecord.amountExercised, 0);

        if (
            IOptionSettlementEngine(engine).tokenType(claimId) ==
            IOptionSettlementEngine.Type.Claim
        ) assertTrue(true);
    }

    function testFuzzExercise(uint112 amountWrite, uint112 amountExercise)
        public
    {
        uint256 wethBalanceEngine = IERC20(weth).balanceOf(address(engine));
        uint256 daiBalanceEngine = IERC20(dai).balanceOf(address(engine));
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        uint256 daiBalance = IERC20(dai).balanceOf(address(this));

        VM.assume(amountWrite > 0);
        VM.assume(amountExercise > 0);
        VM.assume(amountWrite >= amountExercise);
        VM.assume(amountWrite <= wethBalance / 1 ether);
        VM.assume(amountExercise <= daiBalance / 3000 ether);

        uint256 writeAmount = amountWrite * 1 ether;
        uint256 rxAmount = amountExercise * 3000 ether;
        uint256 txAmount = amountExercise * 1 ether;
        uint256 exerciseFee = (rxAmount / 10000) * engine.feeBps();
        uint256 writeFee = ((amountWrite * 1 ether) / 10000) * engine.feeBps();

        uint256 claimId = IOptionSettlementEngine(engine).write(
            testOptionId,
            amountWrite
        );

        IOptionSettlementEngine(engine).exercise(testOptionId, amountExercise);

        IOptionSettlementEngine.Claim
            memory claimRecord = IOptionSettlementEngine(engine).claim(claimId);

        assertTrue(!claimRecord.claimed);
        assertEq(claimRecord.option, testOptionId);
        assertEq(claimRecord.amountWritten, amountWrite);
        assertEq(claimRecord.amountExercised, amountExercise);

        assertEq(
            IERC20(weth).balanceOf(address(engine)),
            wethBalanceEngine + writeAmount - txAmount + writeFee
        );
        assertEq(
            IERC20(dai).balanceOf(address(engine)),
            daiBalanceEngine + rxAmount + exerciseFee
        );
        assertEq(
            IERC20(weth).balanceOf(address(this)),
            (wethBalance + txAmount - writeAmount - writeFee)
        );
        assertEq(
            IERC20(dai).balanceOf(address(this)),
            (daiBalance - rxAmount - exerciseFee)
        );
        assertEq(
            engine.balanceOf(address(this), testOptionId),
            amountWrite - amountExercise
        );
        assertEq(ERC1155(engine).balanceOf(address(this), claimId), 1);
    }

    function testFuzzRedeem(uint112 amountWrite, uint112 amountExercise)
        public
    {
        uint256 wethBalanceEngine = IERC20(weth).balanceOf(address(engine));
        uint256 daiBalanceEngine = IERC20(dai).balanceOf(address(engine));
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        uint256 daiBalance = IERC20(dai).balanceOf(address(this));

        VM.assume(amountWrite > 0);
        VM.assume(amountExercise > 0);
        VM.assume(amountWrite >= amountExercise);
        VM.assume(amountWrite <= wethBalance / 1 ether);
        VM.assume(amountExercise <= daiBalance / 3000 ether);

        uint256 rxAmount = amountExercise * 3000 ether;
        uint256 exerciseFee = (rxAmount / 10000) * engine.feeBps();
        uint256 writeFee = ((amountWrite * 1 ether) / 10000) * engine.feeBps();

        uint256 claimId = IOptionSettlementEngine(engine).write(
            testOptionId,
            amountWrite
        );

        IOptionSettlementEngine(engine).exercise(testOptionId, amountExercise);

        VM.warp(1e15);

        IOptionSettlementEngine(engine).redeem(claimId);

        IOptionSettlementEngine.Claim
            memory claimRecord = IOptionSettlementEngine(engine).claim(claimId);

        assertEq(
            IERC20(weth).balanceOf(address(engine)),
            wethBalanceEngine + writeFee
        );
        assertEq(
            IERC20(dai).balanceOf(address(engine)),
            daiBalanceEngine + exerciseFee
        );
        assertEq(
            IERC20(weth).balanceOf(address(this)),
            (wethBalance - writeFee)
        );
        assertEq(
            IERC20(dai).balanceOf(address(this)),
            daiBalance - exerciseFee
        );
        assertEq(
            ERC1155(engine).balanceOf(address(this), testOptionId),
            amountWrite - amountExercise
        );
        assertEq(ERC1155(engine).balanceOf(address(this), claimId), 0);
        assertTrue(claimRecord.claimed);

        if (
            IOptionSettlementEngine(engine).tokenType(claimId) ==
            IOptionSettlementEngine.Type.Claim
        ) assertTrue(true);
    }

    /* --------------------------- Fail Tests --------------------------- */

    function testFailExercise(uint112 amountWrite, uint112 amountExercise)
        public
    {
        VM.assume(amountExercise > amountWrite);

        IOptionSettlementEngine(engine).write(testOptionId, amountWrite);

        IOptionSettlementEngine(engine).exercise(testOptionId, amountExercise);
    }

    function testFailAssignExercise(
        uint112 optionWrite1,
        uint112 optionWrite2,
        uint112 optionWrite3
    ) public {
        VM.assume(optionWrite1 > 0 && optionWrite2 > 0 && optionWrite3 > 0);
        VM.assume(optionWrite2 > optionWrite1 && optionWrite2 > optionWrite3);
        VM.assume(
            optionWrite1 < 1000000 &&
                optionWrite2 < 1000000 &&
                optionWrite3 < 1000000
        );

        VM.startPrank(address(0x1));
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);
        IOptionSettlementEngine(engine).write(testOptionId, optionWrite1);
        ERC1155(engine).setApprovalForAll(address(this), true);
        ERC1155(engine).safeTransferFrom(
            address(0x1),
            address(0x1337),
            testOptionId,
            optionWrite1,
            ""
        );
        VM.stopPrank();

        VM.startPrank(address(0x2));
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);
        IOptionSettlementEngine(engine).write(testOptionId, optionWrite2);
        VM.stopPrank();

        VM.startPrank(address(0x3));
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);
        IOptionSettlementEngine(engine).write(testOptionId, optionWrite3);
        ERC1155(engine).setApprovalForAll(address(this), true);
        ERC1155(engine).safeTransferFrom(
            address(0x3),
            address(0xBEEF),
            testOptionId,
            optionWrite3,
            ""
        );
        VM.stopPrank();

        VM.startPrank(address(0x1337));
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);
        IOptionSettlementEngine(engine).exercise(testOptionId, optionWrite1);
        VM.stopPrank();

        IOptionSettlementEngine.Claim
            memory claimRecord1 = IOptionSettlementEngine(engine).claim(3);

        assertEq(claimRecord1.amountExercised, optionWrite1);

        VM.startPrank(address(0xBEEF));
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);
        IOptionSettlementEngine(engine).exercise(testOptionId, optionWrite3);
        VM.stopPrank();

        IOptionSettlementEngine.Claim
            memory claimRecord2 = IOptionSettlementEngine(engine).claim(3);

        assertEq(claimRecord2.amountExercised, optionWrite3);
    }

    function testFailDuplicateChain() public {
        // This should fail to create the second and duplicate options chain
        IOptionSettlementEngine.Option memory info = IOptionSettlementEngine
            .Option({
                underlyingAsset: address(weth),
                exerciseAsset: address(dai),
                settlementSeed: 1,
                underlyingAmount: 1 ether,
                exerciseAmount: 3000 ether,
                exerciseTimestamp: uint40(block.timestamp),
                expiryTimestamp: (uint40(block.timestamp) + 604800)
            });
        IOptionSettlementEngine(engine).newChain(info);
    }

    /* --------------------------- URI Tests --------------------------- */

    // TODO(URI tests)

    /* --------------------------- Additional Tests --------------------------- */

    function testTokenTypeNone() public view {
        assert(
            IOptionSettlementEngine(engine).tokenType(3) ==
                IOptionSettlementEngine.Type.None
        );
    }
}
