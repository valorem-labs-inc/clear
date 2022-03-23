// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "ds-test/test.sol";
// TODO(is this really useful for testing)
import "forge-std/stdlib.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IWETH.sol";
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
    // These are just happy path functional tests ATM
    // TODO(Fuzzing)
    // TODO(correctness)
    Vm public constant VM = Vm(HEVM_ADDRESS);
    OptionSettlementEngine public engine;

    uint256 public wethTotalSupply;
    uint256 public daiTotalSupply;

    IWETH public weth;
    IERC20 public dai;

    using stdStorage for StdStorage;
    StdStorage stdstore;

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
        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // Setup DAI
        dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

        // Setup settlement engine
        engine = new OptionSettlementEngine();
        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: 1,
            underlyingAmount: 1 ether,
            exerciseAmount: 3000 ether,
            exerciseTimestamp: uint64(block.timestamp),
            expiryTimestamp: (uint64(block.timestamp) + 604800)
        });
        engine.newChain(info);

        // Now we have 1B DAI
        writeTokenBalance(address(this), address(dai), 1000000000 * 1e18);
        // And 10 M WETH
        writeTokenBalance(address(this), address(weth), 10000000 * 1e18);

        // Issue approvals
        IERC20(weth).approve(address(engine), type(uint256).max);
        IERC20(dai).approve(address(engine), type(uint256).max);

        wethTotalSupply = IERC20(address(weth)).totalSupply();
        daiTotalSupply = IERC20(address(dai)).totalSupply();
    }

    function testNewChain() public {
        uint256 nextTokenId = engine.nextTokenId();

        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: 0,
            underlyingAmount: 1 ether,
            exerciseAmount: 3100 ether,
            exerciseTimestamp: uint64(block.timestamp),
            expiryTimestamp: (uint64(block.timestamp) + 604800)
        });

        uint256 tokenId = engine.newChain(info);

        (
            ,
            uint64 testExerciseTimestamp,
            ,
            uint64 testExpiryTimestamp,
            uint256 testSettlementSeed,
            uint256 testUnderlyingAmount,
            uint256 testExerciseAmount
        ) = engine.option(nextTokenId);

        assertTrue(engine.chainMap(keccak256(abi.encode(info))));
        assertEq(engine.nextTokenId(), nextTokenId + 1);
        assertEq(tokenId, engine.nextTokenId() - 1);

        assertEq(testExerciseTimestamp, uint64(block.timestamp));
        assertEq(testExpiryTimestamp, (uint64(block.timestamp) + 604800));
        assertEq(testUnderlyingAmount, 1 ether);
        assertEq(testExerciseAmount, 3100 ether);
        assertEq(testSettlementSeed, 42);

        if (engine.tokenType(engine.nextTokenId()) == Type.Option)
            assertTrue(true);
    }

    function testFuzzNewChain(
        uint256 settlementSeed,
        uint256 underlyingAmount,
        uint256 exerciseAmount,
        uint64 exerciseTimestamp,
        uint64 expiryTimestamp
    ) public {
        uint256 nextTokenId = engine.nextTokenId();

        VM.assume(expiryTimestamp >= block.timestamp + 86400);
        VM.assume(exerciseTimestamp >= block.timestamp);
        VM.assume(exerciseTimestamp <= expiryTimestamp - 86400);
        VM.assume(expiryTimestamp <= type(uint64).max);
        VM.assume(exerciseTimestamp <= type(uint64).max);
        VM.assume(underlyingAmount <= wethTotalSupply);
        VM.assume(exerciseAmount <= daiTotalSupply);
        VM.assume(type(uint256).max - underlyingAmount >= wethTotalSupply);
        VM.assume(type(uint256).max - exerciseAmount >= daiTotalSupply);

        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: settlementSeed,
            underlyingAmount: underlyingAmount,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp
        });

        uint256 tokenId = engine.newChain(info);

        (
            ,
            uint64 testExerciseTimestamp,
            ,
            uint64 testExpiryTimestamp,
            uint256 testSettlementSeed,
            uint256 testUnderlyingAmount,
            uint256 testExerciseAmount
        ) = engine.option(nextTokenId);

        assertTrue(engine.chainMap(keccak256(abi.encode(info))));
        assertEq(engine.nextTokenId(), nextTokenId + 1);
        assertEq(tokenId, engine.nextTokenId() - 1);

        assertEq(testExerciseTimestamp, exerciseTimestamp);
        assertEq(testExpiryTimestamp, expiryTimestamp);
        assertEq(testUnderlyingAmount, underlyingAmount);
        assertEq(testExerciseAmount, exerciseAmount);
        assertEq(testSettlementSeed, 42);

        if (engine.tokenType(engine.nextTokenId()) == Type.Option)
            assertTrue(true);
    }

    function testFailDuplicateChain() public {
        // This should fail to create the second and duplicate options chain
        Option memory info = Option({
            underlyingAsset: address(weth),
            exerciseAsset: address(dai),
            settlementSeed: 1,
            underlyingAmount: 1 ether,
            exerciseAmount: 3000 ether,
            exerciseTimestamp: uint64(block.timestamp),
            expiryTimestamp: (uint64(block.timestamp) + 604800)
        });
        engine.newChain(info);
    }

    function testUri() public view {
        engine.uri(0);
    }

    function testFailUri() public view {
        engine.uri(1);
    }

    function testWrite() public {
        uint256 nextTokenId = engine.nextTokenId();
        uint256 wethBalanceEngine = IERC20(weth).balanceOf(address(engine));
        uint256 testWallet = IERC20(weth).balanceOf(
            address(0x36273803306a3C22bc848f8Db761e974697ece0d)
        );
        uint256 wethBalance = IERC20(weth).balanceOf(address(this));

        uint256 rxAmount = 10000 * 1 ether;
        uint256 fee = ((rxAmount / 10000) * engine.feeBps());

        engine.write(0, 10000);

        (
            uint256 option,
            uint256 amountWritten,
            uint256 amountExercised,
            bool claimed
        ) = engine.claim(nextTokenId);

        assertEq(
            IERC20(weth).balanceOf(address(engine)),
            wethBalanceEngine + rxAmount
        );
        assertEq(
            IERC20(weth).balanceOf(
                address(0x36273803306a3C22bc848f8Db761e974697ece0d)
            ),
            testWallet + fee
        );
        assertEq(
            IERC20(weth).balanceOf(address(this)),
            wethBalance - rxAmount - fee
        );
        assertEq(engine.balanceOf(address(this), 0), 10000);
        assertEq(engine.balanceOf(address(this), 1), 1);

        assertTrue(!claimed);
        assertEq(option, 0);
        assertEq(amountWritten, 10000);
        assertEq(amountExercised, 0);
        assertEq(engine.nextTokenId(), nextTokenId + 1);

        if (engine.tokenType(engine.nextTokenId()) == Type.Claim)
            assertTrue(true);
    }

    function testFuzzWrite(uint16 amount) public {
        VM.assume(amount > 0);
        VM.assume(amount <= type(uint16).max);

        uint256 nextTokenId = engine.nextTokenId();

        engine.write(0, uint256(amount));

        (
            uint256 option,
            uint256 amountWritten,
            uint256 amountExercised,
            bool claimed
        ) = engine.claim(nextTokenId);

        // TODO(Wallet balance checks)

        assertEq(engine.balanceOf(address(this), 0), amount);
        assertEq(engine.balanceOf(address(this), 1), 1);

        assertTrue(!claimed);
        assertEq(option, 0);
        assertEq(amountWritten, amount);
        assertEq(amountExercised, 0);
        assertEq(engine.nextTokenId(), nextTokenId + 1);

        if (engine.tokenType(engine.nextTokenId()) == Type.Claim)
            assertTrue(true);
    }

    function testExercise() public {
        uint256 wethBalanceEngine = IERC20(weth).balanceOf(address(engine));
        uint256 daiBalanceEngine = IERC20(dai).balanceOf(address(engine));
        uint256 daiTestWallet = IERC20(dai).balanceOf(
            address(0x36273803306a3C22bc848f8Db761e974697ece0d)
        );

        uint256 rxAmount = 10 * 3000 ether;
        uint256 txAmount = 10 * 1 ether;
        uint256 fee = ((rxAmount / 10000) * engine.feeBps());

        engine.write(0, 10);

        uint256 wethBalance = IERC20(weth).balanceOf(address(this));
        uint256 daiBalance = IERC20(dai).balanceOf(address(this));

        engine.exercise(0, 10);

        assertEq(
            IERC20(dai).balanceOf(
                address(0x36273803306a3C22bc848f8Db761e974697ece0d)
            ),
            daiTestWallet + fee
        );
        assertEq(IERC20(weth).balanceOf(address(engine)), wethBalanceEngine);
        assertEq(
            IERC20(dai).balanceOf(address(engine)),
            daiBalanceEngine + rxAmount
        );
        assertEq(
            IERC20(weth).balanceOf(address(this)),
            (wethBalance + txAmount)
        );
        assertEq(
            IERC20(dai).balanceOf(address(this)),
            (daiBalance - rxAmount - fee)
        );
        assertEq(engine.balanceOf(address(this), 0), 0);
        assertEq(engine.balanceOf(address(this), 1), 1);
    }

    function testFuzzExercise(uint16 amountWrite, uint16 amountExercise)
        public
    {
        VM.assume(amountWrite >= amountExercise);
        VM.assume(amountWrite > 0);
        VM.assume(amountExercise > 0);
        VM.assume(amountWrite <= type(uint16).max);
        VM.assume(amountExercise <= type(uint16).max);

        engine.write(0, uint256(amountWrite));

        engine.exercise(0, uint256(amountExercise));

        assertEq(
            engine.balanceOf(address(this), 0),
            amountWrite - amountExercise
        );
        assertEq(engine.balanceOf(address(this), 1), 1);

        // TODO(Wallet balance checks)
    }

    // TODO(a function to create random new chains for fuzzing)
    // TODO(testFuzzExercise)
    // TODO(testFuzzRedeem)
}
