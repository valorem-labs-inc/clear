// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "./MockERC20.sol";

import "../../src/ValoremOptionsClearinghouse.sol";

/// @notice Base for ValoremOptionsClearinghouse test suite
abstract contract BaseClearinghouseTest is Test {
    using stdStorage for StdStorage;

    ValoremOptionsClearinghouse internal clearinghouse;
    ITokenURIGenerator internal generator;

    // Scalars
    uint256 internal constant WAD = 1e18;

    // Users
    address internal constant ALICE = address(0xA);
    address internal constant BOB = address(0xB);
    address internal constant CAROL = address(0xC);

    // Admin
    address internal constant FEE_TO = address(0xBEEF);

    // Tokens
    IERC20 internal WETHLIKE;
    IERC20 internal DAILIKE;
    IERC20 internal USDCLIKE;
    IERC20 internal UNILIKE;
    IERC20 internal ERC20A;
    IERC20 internal ERC20B;
    IERC20 internal ERC20C;
    IERC20 internal ERC20D;
    IERC20 internal ERC20E;
    IERC20 internal ERC20F;

    IERC20[] public ERC20S;

    uint256 internal constant STARTING_BALANCE = 1_000_000_000 * 1e18;
    uint256 internal constant STARTING_BALANCE_USDC = 1_000_000_000 * 1e6;
    uint256 internal constant STARTING_BALANCE_WETH = 1_000_000 * 1e18;

    // Test option
    uint256 internal testOptionId;
    address internal testUnderlyingAsset;
    uint40 internal testExerciseTimestamp;
    uint40 internal testExpiryTimestamp;
    address internal testExerciseAsset;
    uint96 internal testUnderlyingAmount = 7 ether; // Uneven number to test for division rounding
    uint96 internal testExerciseAmount = 3000 ether;
    uint256 internal testDuration = 1 days;
    IValoremOptionsClearinghouse.Option internal testOption;

    function setUp() public virtual {
        // Deploy ValoremOptionsClearinghouse
        generator = new TokenURIGenerator();
        clearinghouse = new ValoremOptionsClearinghouse(FEE_TO, address(generator));

        // Enable fee switch
        vm.prank(FEE_TO);
        clearinghouse.setFeesEnabled(true);

        // Deploy mock ERC20 contracts
        WETHLIKE = IERC20(address(new MockERC20("Wrapped Ether", "WETH", 18)));
        DAILIKE = IERC20(address(new MockERC20("Dai", "DAI", 18)));
        USDCLIKE = IERC20(address(new MockERC20("USD Coin", "USDC", 6)));
        UNILIKE = IERC20(address(new MockERC20("Uniswap", "UNI", 18)));
        ERC20A = IERC20(address(new MockERC20("Mock ERC20 A", "ERC20A", 18)));
        ERC20B = IERC20(address(new MockERC20("Mock ERC20 B", "ERC20B", 18)));
        ERC20C = IERC20(address(new MockERC20("Mock ERC20 C", "ERC20C", 18)));
        ERC20D = IERC20(address(new MockERC20("Mock ERC20 D", "ERC20D", 18)));
        ERC20E = IERC20(address(new MockERC20("Mock ERC20 E", "ERC20E", 18)));
        ERC20F = IERC20(address(new MockERC20("Mock ERC20 F", "ERC20F", 18)));
        ERC20S.push(ERC20A);
        ERC20S.push(ERC20B);
        ERC20S.push(ERC20C);
        ERC20S.push(ERC20D);
        ERC20S.push(ERC20E);
        ERC20S.push(ERC20F);

        // Setup token balances and approvals
        address[3] memory recipients = [ALICE, BOB, CAROL];
        for (uint256 i = 0; i < recipients.length; i++) {
            _mintTokensForAddress(recipients[i]);
        }

        // Setup test option
        testUnderlyingAsset = address(WETHLIKE);
        testExerciseAsset = address(DAILIKE);
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
    }

    /*//////////////////////////////////////////////////////////////
    //  Accessors
    //////////////////////////////////////////////////////////////*/
    function getMockErc20s() public view returns (IERC20[] memory) {
        return ERC20S;
    }

    /*//////////////////////////////////////////////////////////////
    //  Test Helpers -- General
    //////////////////////////////////////////////////////////////*/

    // function _mockTotalSupply(address token)  {
    //     vm.mock
    // }
    function _mintTokensForAddress(address recipient) internal {
        // Now we have 1B in stables and 10M WETH
        _mint(recipient, MockERC20(address(WETHLIKE)), STARTING_BALANCE_WETH);
        _mint(recipient, MockERC20(address(DAILIKE)), STARTING_BALANCE);
        _mint(recipient, MockERC20(address(USDCLIKE)), STARTING_BALANCE_USDC);
        _mint(recipient, MockERC20(address(UNILIKE)), STARTING_BALANCE);

        for (uint256 i = 0; i < ERC20S.length; i++) {
            _mint(recipient, MockERC20(address(ERC20S[i])), STARTING_BALANCE);
        }

        // Approve settlement engine to spend ERC20 token balances on behalf of user
        vm.startPrank(recipient);
        WETHLIKE.approve(address(clearinghouse), type(uint256).max);
        DAILIKE.approve(address(clearinghouse), type(uint256).max);
        USDCLIKE.approve(address(clearinghouse), type(uint256).max);
        UNILIKE.approve(address(clearinghouse), type(uint256).max);

        for (uint256 i = 0; i < ERC20S.length; i++) {
            ERC20S[i].approve(address(clearinghouse), type(uint256).max);
        }
        vm.stopPrank();
    }

    function _mint(address who, MockERC20 token, uint256 amount) internal {
        token.mint(who, amount);
    }

    function _writeTokenBalance(address who, address token, uint256 amount) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amount);
    }

    /// @dev probability in bips
    function _coinflip(uint32 seed, uint16 probability) internal pure returns (bool) {
        return _randBetween(seed, 10000) < probability;
    }

    function _randBetween(uint32 seed, uint256 max) internal pure returns (uint256) {
        uint256 h = uint256(keccak256(abi.encode(seed)));
        return h % max;
    }

    /*//////////////////////////////////////////////////////////////
    //  Test Helpers -- Working with Options, Claims, etc.
    //////////////////////////////////////////////////////////////*/

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
    ) internal returns (uint256 optionId, IValoremOptionsClearinghouse.Option memory option) {
        (, option) = _getNewOptionType({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp
        });
        optionId = clearinghouse.newOptionType({
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
    ) internal pure returns (uint256 optionId, IValoremOptionsClearinghouse.Option memory option) {
        option = IValoremOptionsClearinghouse.Option({
            underlyingAsset: underlyingAsset,
            underlyingAmount: underlyingAmount,
            exerciseAsset: exerciseAsset,
            exerciseAmount: exerciseAmount,
            exerciseTimestamp: exerciseTimestamp,
            expiryTimestamp: expiryTimestamp,
            settlementSeed: 0, // default zero for settlement seed
            nextClaimKey: 0 // default zero for next claim id
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
            claimId = clearinghouse.write(optionId, toWrite);
            clearinghouse.safeTransferFrom(writer, exerciser, optionId, toWrite, "");
            vm.stopPrank();
        }

        if (toExercise > 0) {
            vm.warp(testExerciseTimestamp + 1);
            vm.startPrank(exerciser);
            clearinghouse.exercise(optionId, toExercise);
            vm.stopPrank();
        }
    }

    function _getDaysBucket() internal view returns (uint16) {
        return uint16(block.timestamp / 1 days);
    }

    function _getDaysFromBucket(uint256 ts, uint16 daysFrom) internal pure returns (uint16) {
        return uint16((ts + daysFrom * 1 days) / 1 days);
    }

    function _createOptionIdFromStruct(IValoremOptionsClearinghouse.Option memory optionInfo)
        internal
        pure
        returns (uint256)
    {
        uint160 optionKey = uint160(
            bytes20(
                keccak256(
                    abi.encode(
                        optionInfo.underlyingAsset,
                        optionInfo.underlyingAmount,
                        optionInfo.exerciseAsset,
                        optionInfo.exerciseAmount,
                        optionInfo.exerciseTimestamp,
                        optionInfo.expiryTimestamp
                    )
                )
            )
        );

        return uint256(optionKey) << 96;
    }

    /*//////////////////////////////////////////////////////////////
    //  Test Helpers -- Protocol Fee
    //////////////////////////////////////////////////////////////*/

    function _calculateFee(uint256 amount) internal view returns (uint256) {
        uint256 fee = (amount * clearinghouse.feeBps()) / 10_000;
        if (fee == 0) {
            fee = 1;
        }
        return fee;
    }

    /*//////////////////////////////////////////////////////////////
    //  Test Helpers -- Assertions
    //////////////////////////////////////////////////////////////*/

    function _assertTokenIsNone(uint256 tokenId) internal {
        if (clearinghouse.tokenType(tokenId) != IValoremOptionsClearinghouse.TokenType.None) {
            assertTrue(false);
        }
    }

    function _assertTokenIsClaim(uint256 tokenId) internal {
        if (clearinghouse.tokenType(tokenId) != IValoremOptionsClearinghouse.TokenType.Claim) {
            assertTrue(false);
        }
    }

    function _assertTokenIsOption(uint256 tokenId) internal {
        if (clearinghouse.tokenType(tokenId) != IValoremOptionsClearinghouse.TokenType.Option) {
            assertTrue(false);
        }
    }

    function _assertPosition(int256 actual, uint96 expected) internal {
        uint96 _actual = uint96(int96(actual));
        assertEq(_actual, expected);
    }

    function _assertClaimAmountExercised(uint256 claimId, uint112 amount, string memory where) internal {
        IValoremOptionsClearinghouse.Position memory position = clearinghouse.position(claimId);
        IValoremOptionsClearinghouse.Option memory option = clearinghouse.option(claimId);
        uint112 amountExercised = uint112(uint256(position.exerciseAmount) / option.exerciseAmount);
        assertEq(amount, amountExercised, where);
    }

    function _assertClaimAmountExercised(uint256 claimId, uint112 amount) internal {
        _assertClaimAmountExercised(claimId, amount, "");
    }

    function assertEq(
        IValoremOptionsClearinghouse.Option memory actual,
        IValoremOptionsClearinghouse.Option memory expected
    ) public {
        assertEq(actual.underlyingAsset, expected.underlyingAsset);
        assertEq(actual.underlyingAmount, expected.underlyingAmount);
        assertEq(actual.exerciseAsset, expected.exerciseAsset);
        assertEq(actual.exerciseAmount, expected.exerciseAmount);
        assertEq(actual.exerciseTimestamp, expected.exerciseTimestamp);
        assertEq(actual.expiryTimestamp, expected.expiryTimestamp);
        assertEq(actual.settlementSeed, expected.settlementSeed);
        assertEq(actual.nextClaimKey, expected.nextClaimKey);
    }

    /*//////////////////////////////////////////////////////////////
    //  Duplicated from Contract -- Constants
    //////////////////////////////////////////////////////////////*/

    uint8 internal constant OPTION_ID_PADDING = 96;

    uint96 internal constant CLAIM_NUMBER_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFF;

    /*//////////////////////////////////////////////////////////////
    //  Duplicated from Contract -- Encode/Decode Token IDs
    //////////////////////////////////////////////////////////////*/

    function encodeTokenId(uint160 optionKey, uint96 claimKey) internal pure returns (uint256 tokenId) {
        tokenId |= uint256(optionKey) << OPTION_ID_PADDING;
        tokenId |= uint256(claimKey);
    }

    function decodeTokenId(uint256 tokenId) internal pure returns (uint160 optionKey, uint96 claimKey) {
        // move key to lsb to fit into uint160
        optionKey = uint160(tokenId >> OPTION_ID_PADDING);

        // grab lower 96b of id for claim number
        claimKey = uint96(tokenId & CLAIM_NUMBER_MASK);
    }

    /*//////////////////////////////////////////////////////////////
    //  Duplicated from Contract -- Events
    //////////////////////////////////////////////////////////////*/

    event NewOptionType(
        uint256 optionId,
        address indexed exerciseAsset,
        address indexed underlyingAsset,
        uint96 exerciseAmount,
        uint96 underlyingAmount,
        uint40 exerciseTimestamp,
        uint40 indexed expiryTimestamp
    );

    event OptionsWritten(uint256 indexed optionId, address indexed writer, uint256 indexed claimId, uint112 amount);

    event ClaimRedeemed(
        uint256 indexed claimId,
        uint256 indexed optionId,
        address indexed redeemer,
        uint256 exerciseAmountRedeemed,
        uint256 underlyingAmountRedeemed
    );

    event BucketWrittenInto(
        uint256 indexed optionId, uint256 indexed claimId, uint96 indexed bucketIndex, uint112 amount
    );

    event BucketAssignedExercise(uint256 indexed optionId, uint96 indexed bucketIndex, uint112 amountAssigned);

    event OptionsExercised(uint256 indexed optionId, address indexed exerciser, uint112 amount);

    event FeeAccrued(uint256 indexed optionId, address indexed asset, address indexed payer, uint256 amount);

    event FeeSwept(address indexed asset, address indexed feeTo, uint256 amount);

    event FeeSwitchUpdated(address feeTo, bool enabled);

    event FeeToUpdated(address indexed newFeeTo);

    event TokenURIGeneratorUpdated(address indexed newTokenURIGenerator);
}
