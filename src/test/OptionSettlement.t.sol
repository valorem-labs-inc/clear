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
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IERC20 public weth = IERC20(WETH);
    IERC20 public dai = IERC20(DAI);
    IERC20 public usdc = IERC20(USDC);

    uint256 public wethTotalSupply;
    uint256 public daiTotalSupply;

    uint256 public testOptionId;
    IOptionSettlementEngine.Option public option;

    address public alice = address(0xA);
    address public bob = address(0xB);
    address public carol = address(0xC);
    address public dave = address(0xD);
    address public eve = address(0xE);

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
        dai = IERC20(DAI);
        usdc = IERC20(USDC);
        weth = IERC20(WETH);

        engine = new OptionSettlementEngine();

        option = IOptionSettlementEngine.Option({
            underlyingAsset: WETH,
            exerciseAsset: DAI,
            settlementSeed: 1234567,
            underlyingAmount: 1 ether,
            exerciseAmount: 3000 ether,
            exerciseTimestamp: uint40(block.timestamp),
            expiryTimestamp: (uint40(block.timestamp) + 604800)
        });
        testOptionId = engine.newChain(option);

        // // Now we have 1B DAI and 1B USDC
        writeTokenBalance(address(this), DAI, 1000000000 * 1e18);
        writeTokenBalance(address(this), USDC, 1000000000 * 1e6);
        // // And 10 M WETH
        writeTokenBalance(address(this), WETH, 10000000 * 1e18);

        weth.approve(address(engine), type(uint256).max);
        dai.approve(address(engine), type(uint256).max);

        // pre-load balances and approvals
        address[6] memory recipients = [
            address(engine),
            alice,
            bob,
            carol,
            dave,
            eve
        ];
        for (uint256 i = 0; i == 6; i++) {
            address recipient = recipients[i];
            writeTokenBalance(recipient, DAI, 1000000000 * 1e18);
            writeTokenBalance(recipient, USDC, 1000000000 * 1e6);
            writeTokenBalance(recipient, WETH, 10000000 * 1e18);

            VM.startPrank(recipient);
            weth.approve(address(engine), type(uint256).max);
            dai.approve(address(engine), type(uint256).max);
            engine.setApprovalForAll(address(this), true);
            VM.stopPrank();
        }

        wethTotalSupply = IERC20(weth).totalSupply();
        daiTotalSupply = IERC20(dai).totalSupply();
    }

    /* --------------------------- Pass Tests --------------------------- */
    // function testPassExerciseSinglePartial() public {

    // }

    // function testPassExerciseManyNotPartial() public {

    // }

    // function testPassExerciseManyAndAPartial() public {

    // }

    // function testPassWriteAdditionalAmount() public {

    // }

    /* --------------------------- Fail Tests --------------------------- */

    function testFailExercise(uint112 amountWrite, uint112 amountExercise)
        public
    {
        VM.assume(amountExercise > amountWrite);

        engine.write(testOptionId, amountWrite);

        engine.exercise(testOptionId, amountExercise);
    }

    function testFailAssignExercise(
        uint112 amount1,
        uint112 amount2,
        uint112 amount3
    ) public {
        VM.assume(amount1 > 0 && amount2 > 0 && amount3 > 0);
        VM.assume(amount2 > amount1 && amount2 > amount3);
        VM.assume(amount1 < 1000000 && amount2 < 1000000 && amount3 < 1000000);

        VM.startPrank(carol);
        engine.write(testOptionId, amount1);
        engine.setApprovalForAll(address(this), true);
        engine.safeTransferFrom(carol, bob, testOptionId, amount1, "");
        VM.stopPrank();

        VM.startPrank(dave);
        engine.write(testOptionId, amount2);
        VM.stopPrank();

        VM.startPrank(eve);
        engine.write(testOptionId, amount3);
        engine.setApprovalForAll(address(this), true);
        engine.safeTransferFrom(eve, alice, testOptionId, amount3, "");
        VM.stopPrank();

        VM.startPrank(bob);
        engine.exercise(testOptionId, amount1);
        VM.stopPrank();

        IOptionSettlementEngine.Claim memory claimRecord1 = engine.claim(3);

        assertEq(claimRecord1.amountExercised, amount1);

        VM.startPrank(alice);
        engine.exercise(testOptionId, amount3);
        VM.stopPrank();

        IOptionSettlementEngine.Claim memory claimRecord2 = engine.claim(3);

        assertEq(claimRecord2.amountExercised, amount3);
    }

    function testFailDuplicateChain() public {
        engine.newChain(option);
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
                underlyingAsset: WETH,
                exerciseAsset: DAI,
                settlementSeed: 0,
                underlyingAmount: underlyingAmount,
                exerciseAmount: exerciseAmount,
                exerciseTimestamp: exerciseTimestamp,
                expiryTimestamp: expiryTimestamp
            });

        uint256 optionId = engine.newChain(optionInfo);
        assertEq(optionId, 2);

        IOptionSettlementEngine.Option memory optionRecord = engine.option(
            optionId
        );

        assertEq(
            engine.hashToOptionToken(keccak256(abi.encode(optionInfo))),
            optionId
        );
        assertEq(optionRecord.underlyingAsset, WETH);
        assertEq(optionRecord.exerciseAsset, DAI);
        assertEq(optionRecord.exerciseTimestamp, exerciseTimestamp);
        assertEq(optionRecord.expiryTimestamp, expiryTimestamp);
        assertEq(optionRecord.underlyingAmount, underlyingAmount);
        assertEq(optionRecord.exerciseAmount, exerciseAmount);
        assertEq(optionRecord.settlementSeed, 0);

        if (engine.tokenType(optionId) == IOptionSettlementEngine.Type.Option)
            assertTrue(true);
    }

    function testFuzzWrite(uint112 amountWrite) public {
        uint256 wethBalanceEngine = weth.balanceOf(address(engine));
        uint256 wethBalance = weth.balanceOf(address(this));

        VM.assume(amountWrite > 0);
        VM.assume(amountWrite <= wethBalance / 1 ether);

        uint256 rxAmount = amountWrite * 1 ether;
        uint256 fee = ((rxAmount / 10000) * engine.feeBps());

        uint256 claimId = engine.write(testOptionId, amountWrite);

        IOptionSettlementEngine.Claim memory claimRecord = engine.claim(
            claimId
        );

        assertEq(
            weth.balanceOf(address(engine)),
            wethBalanceEngine + rxAmount + fee
        );
        assertEq(weth.balanceOf(address(this)), wethBalance - rxAmount - fee);

        assertEq(engine.balanceOf(address(this), testOptionId), amountWrite);
        assertEq(engine.balanceOf(address(this), claimId), 1);
        assertTrue(!claimRecord.claimed);
        assertEq(claimRecord.option, testOptionId);
        assertEq(claimRecord.amountWritten, amountWrite);
        assertEq(claimRecord.amountExercised, 0);

        if (engine.tokenType(claimId) == IOptionSettlementEngine.Type.Claim)
            assertTrue(true);
    }

    function testFuzzExercise(uint112 amountWrite, uint112 amountExercise)
        public
    {
        uint256 wethBalanceEngine = weth.balanceOf(address(engine));
        uint256 daiBalanceEngine = dai.balanceOf(address(engine));
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 daiBalance = dai.balanceOf(address(this));

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

        uint256 claimId = engine.write(testOptionId, amountWrite);

        engine.exercise(testOptionId, amountExercise);

        IOptionSettlementEngine.Claim memory claimRecord = engine.claim(
            claimId
        );

        assertTrue(!claimRecord.claimed);
        assertEq(claimRecord.option, testOptionId);
        assertEq(claimRecord.amountWritten, amountWrite);
        assertEq(claimRecord.amountExercised, amountExercise);

        assertEq(
            weth.balanceOf(address(engine)),
            wethBalanceEngine + writeAmount - txAmount + writeFee
        );
        assertEq(
            dai.balanceOf(address(engine)),
            daiBalanceEngine + rxAmount + exerciseFee
        );
        assertEq(
            weth.balanceOf(address(this)),
            (wethBalance + txAmount - writeAmount - writeFee)
        );
        assertEq(
            dai.balanceOf(address(this)),
            (daiBalance - rxAmount - exerciseFee)
        );
        assertEq(
            engine.balanceOf(address(this), testOptionId),
            amountWrite - amountExercise
        );
        assertEq(engine.balanceOf(address(this), claimId), 1);
    }

    function testFuzzRedeem(uint112 amountWrite, uint112 amountExercise)
        public
    {
        uint256 wethBalanceEngine = weth.balanceOf(address(engine));
        uint256 daiBalanceEngine = dai.balanceOf(address(engine));
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 daiBalance = dai.balanceOf(address(this));

        VM.assume(amountWrite > 0);
        VM.assume(amountExercise > 0);
        VM.assume(amountWrite >= amountExercise);
        VM.assume(amountWrite <= wethBalance / 1 ether);
        VM.assume(amountExercise <= daiBalance / 3000 ether);

        uint256 rxAmount = amountExercise * 3000 ether;
        uint256 exerciseFee = (rxAmount / 10000) * engine.feeBps();
        uint256 writeFee = ((amountWrite * 1 ether) / 10000) * engine.feeBps();

        uint256 claimId = engine.write(testOptionId, amountWrite);

        engine.exercise(testOptionId, amountExercise);

        VM.warp(1e15);

        engine.redeem(claimId);

        IOptionSettlementEngine.Claim memory claimRecord = engine.claim(
            claimId
        );

        assertEq(weth.balanceOf(address(engine)), wethBalanceEngine + writeFee);
        assertEq(
            dai.balanceOf(address(engine)),
            daiBalanceEngine + exerciseFee
        );
        assertEq(weth.balanceOf(address(this)), (wethBalance - writeFee));
        assertEq(dai.balanceOf(address(this)), daiBalance - exerciseFee);
        assertEq(
            engine.balanceOf(address(this), testOptionId),
            amountWrite - amountExercise
        );
        assertEq(engine.balanceOf(address(this), claimId), 0);
        assertTrue(claimRecord.claimed);

        if (engine.tokenType(claimId) == IOptionSettlementEngine.Type.Claim)
            assertTrue(true);
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
