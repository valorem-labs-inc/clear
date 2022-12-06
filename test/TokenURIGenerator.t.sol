// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "../src/OptionSettlementEngine.sol";

contract TokenURIGeneratorTest is Test {
    using stdStorage for StdStorage;

    OptionSettlementEngine internal engine;

    // Time
    uint40 internal constant TIME0 = 2_000_000_000; // now-ish

    // Tokens
    address internal constant WETH_A = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI_A = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC_A = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Users
    address internal constant ALICE = address(0xA);
    address internal constant BOB = address(0xB);

    // Token interfaces
    IERC20 internal constant DAI = IERC20(DAI_A);
    IERC20 internal constant WETH = IERC20(WETH_A);
    IERC20 internal constant USDC = IERC20(USDC_A);

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("RPC_URL"), 15_000_000);
        vm.warp(TIME0);

        // Deploy OptionSettlementEngine
        TokenURIGenerator generator = new TokenURIGenerator();
        engine = new OptionSettlementEngine(address(0xCAFE), address(generator));

        // Setup token balances and approvals for Alice
        _writeTokenBalance(ALICE, DAI_A, 1_000_000_000e18);
        _writeTokenBalance(ALICE, USDC_A, 1_000_000_000e6);
        _writeTokenBalance(ALICE, WETH_A, 10_000_000e18);
        vm.startPrank(ALICE);
        WETH.approve(address(engine), type(uint256).max);
        DAI.approve(address(engine), type(uint256).max);
        USDC.approve(address(engine), type(uint256).max);
        vm.stopPrank();
        // for Bob
        _writeTokenBalance(BOB, DAI_A, 1_000_000_000e18);
        _writeTokenBalance(BOB, USDC_A, 1_000_000_000e6);
        _writeTokenBalance(BOB, WETH_A, 10_000_000e18);
        vm.startPrank(BOB);
        WETH.approve(address(engine), type(uint256).max);
        DAI.approve(address(engine), type(uint256).max);
        USDC.approve(address(engine), type(uint256).max);
        vm.stopPrank();

        // Approve test contract approval for all on settlement engine ERC1155 token balances
        engine.setApprovalForAll(address(this), true);
    }

    // **********************************************************************
    //                            TOKEN URI
    // **********************************************************************

    string internal constant headerJson = "data:application/json;base64,";

    string internal constant json1 = '{"name":"';
    string internal constant contentName = "USDCDAI220622C";
    string internal constant json2 = '", "description": "NFT representing a Valorem options contract. ';
    string internal constant contentUnderlyingSymbol = "USDC";
    string internal constant json3 = " Address: ";
    // contentUnderlyingAddress
    string internal constant json4 = ". ";
    string internal constant contentExerciseSymbol = "DAI";
    // json3
    // contentExerciseAddress
    string internal constant json5 = ' .", "image": "data:image/svg+xml;base64,';
    // contentSvgBase64Encoded
    string internal constant json6 = '"}';

    // string internal constant svg1 = "<svg width='400' height='300' viewBox='0 0 400 300' xmlns='http://www.w3.org/2000/svg'><rect width='100%' height='100%' rx='12' ry='12'  fill='#3E5DC7' /><g transform='scale(5), translate(25, 18)' fill-opacity='0.15'><path xmlns='http://www.w3.org/2000/svg' d='M69.3577 14.5031H29.7265L39.6312 0H0L19.8156 29L29.7265 14.5031L39.6312 29H19.8156H0L19.8156 58L39.6312 29L49.5421 43.5031L69.3577 14.5031Z' fill='white'/></g><text x='16px' y='55px' font-size='32px' fill='#fff' font-family='Helvetica'>";
    // // contentUnderlyingSymbol
    // string internal constant svg2 = " / ";
    // // contentExerciseSymbol
    // string internal constant svg3 = "</text><text x='16px' y='80px' font-size='16' fill='#fff' font-family='Helvetica' font-weight='300'>";
    // // contentLongOrShort
    // string internal constant svg4 = " Call</text><text x='16px' y='116px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>UNDERLYING ASSET</text><text x='16px' y='140px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>";
    // // contentUnderlyingAmount
    // string internal constant svg5 = " ";
    // // contentUnderlyingSymbol
    // string internal constant svg6 = "</text><text x='16px' y='176px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>EXERCISE ASSET</text><text x='16px' y='200px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>";
    // // contentExerciseAmount
    // // svg5
    // // contentExerciseSymbol
    // string internal constant svg8 = "</text><text x='16px' y='236px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>EXERCISE DATE</text><text x='16px' y='260px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>";
    // // contentExerciseDate
    // string internal constant svg9 = "</text><text x='200px' y='236px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>EXPIRY DATE</text><text x='200px' y='260px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>";
    // // contentExpiryDate
    // string internal constant svg10 = "</text></svg>";

    string internal constant svgAll =
        "PHN2ZyB3aWR0aD0nNDAwJyBoZWlnaHQ9JzMwMCcgdmlld0JveD0nMCAwIDQwMCAzMDAnIHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Zyc+PHJlY3Qgd2lkdGg9JzEwMCUnIGhlaWdodD0nMTAwJScgcng9JzEyJyByeT0nMTInICBmaWxsPScjM0U1REM3JyAvPjxnIHRyYW5zZm9ybT0nc2NhbGUoNSksIHRyYW5zbGF0ZSgyNSwgMTgpJyBmaWxsLW9wYWNpdHk9JzAuMTUnPjxwYXRoIHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZycgZD0nTTY5LjM1NzcgMTQuNTAzMUgyOS43MjY1TDM5LjYzMTIgMEgwTDE5LjgxNTYgMjlMMjkuNzI2NSAxNC41MDMxTDM5LjYzMTIgMjlIMTkuODE1NkgwTDE5LjgxNTYgNThMMzkuNjMxMiAyOUw0OS41NDIxIDQzLjUwMzFMNjkuMzU3NyAxNC41MDMxWicgZmlsbD0nd2hpdGUnLz48L2c+PHRleHQgeD0nMTZweCcgeT0nNTVweCcgZm9udC1zaXplPSczMnB4JyBmaWxsPScjZmZmJyBmb250LWZhbWlseT0nSGVsdmV0aWNhJz5VU0RDIC8gREFJPC90ZXh0Pjx0ZXh0IHg9JzE2cHgnIHk9JzgwcHgnIGZvbnQtc2l6ZT0nMTYnIGZpbGw9JyNmZmYnIGZvbnQtZmFtaWx5PSdIZWx2ZXRpY2EnIGZvbnQtd2VpZ2h0PSczMDAnPkxvbmcgQ2FsbDwvdGV4dD48dGV4dCB4PScxNnB4JyB5PScxMTZweCcgZm9udC1zaXplPScxNCcgbGV0dGVyLXNwYWNpbmc9JzAuMDFlbScgZmlsbD0nI2ZmZicgZm9udC1mYW1pbHk9J0hlbHZldGljYSc+VU5ERVJMWUlORyBBU1NFVDwvdGV4dD48dGV4dCB4PScxNnB4JyB5PScxNDBweCcgZm9udC1zaXplPScxOCcgZmlsbD0nI2ZmZicgZm9udC1mYW1pbHk9J0hlbHZldGljYScgZm9udC13ZWlnaHQ9JzMwMCc+MC4wMDAxIFVTREM8L3RleHQ+PHRleHQgeD0nMTZweCcgeT0nMTc2cHgnIGZvbnQtc2l6ZT0nMTQnIGxldHRlci1zcGFjaW5nPScwLjAxZW0nIGZpbGw9JyNmZmYnIGZvbnQtZmFtaWx5PSdIZWx2ZXRpY2EnPkVYRVJDSVNFIEFTU0VUPC90ZXh0Pjx0ZXh0IHg9JzE2cHgnIHk9JzIwMHB4JyBmb250LXNpemU9JzE4JyBmaWxsPScjZmZmJyBmb250LWZhbWlseT0nSGVsdmV0aWNhJyBmb250LXdlaWdodD0nMzAwJz4zMDAwIERBSTwvdGV4dD48dGV4dCB4PScxNnB4JyB5PScyMzZweCcgZm9udC1zaXplPScxNCcgbGV0dGVyLXNwYWNpbmc9JzAuMDFlbScgZmlsbD0nI2ZmZicgZm9udC1mYW1pbHk9J0hlbHZldGljYSc+RVhFUkNJU0UgREFURTwvdGV4dD48dGV4dCB4PScxNnB4JyB5PScyNjBweCcgZm9udC1zaXplPScxOCcgZmlsbD0nI2ZmZicgZm9udC1mYW1pbHk9J0hlbHZldGljYScgZm9udC13ZWlnaHQ9JzMwMCc+MDYvMjEvMjAyMjwvdGV4dD48dGV4dCB4PScyMDBweCcgeT0nMjM2cHgnIGZvbnQtc2l6ZT0nMTQnIGxldHRlci1zcGFjaW5nPScwLjAxZW0nIGZpbGw9JyNmZmYnIGZvbnQtZmFtaWx5PSdIZWx2ZXRpY2EnPkVYUElSWSBEQVRFPC90ZXh0Pjx0ZXh0IHg9JzIwMHB4JyB5PScyNjBweCcgZm9udC1zaXplPScxOCcgZmlsbD0nI2ZmZicgZm9udC1mYW1pbHk9J0hlbHZldGljYScgZm9udC13ZWlnaHQ9JzMwMCc+MDYvMjIvMjAyMjwvdGV4dD48L3N2Zz4=";

    // function jsonHeader() internal pure returns (string memory) {
    //     return 'data:application/json;base64,';
    // }

    // function json1() internal pure returns (string memory) {
    //     return '{"name":"';
    // }

    // function json2() internal pure returns (string memory) {
    //     return '", "description": "NFT representing a Valorem options contract. ';
    // }

    // function json3() internal pure returns (string memory) {
    //     return ' Address: ';
    // }

    // function json4() internal pure returns (string memory) {
    //     return '. ';
    // }

    // function json5() internal pure returns (string memory) {
    //     return ' .", "image": "data:image/svg+xml;base64,';
    // }

    // function json6() internal pure returns (string memory) {
    //     return '"}';
    // }

    function testTokenURIForOption() public {
        string memory expectedOptionUri = string(
            abi.encodePacked(
                headerJson,
                Base64.encode(
                    abi.encodePacked(
                        json1,
                        contentName,
                        json2,
                        contentUnderlyingSymbol,
                        json3,
                        _addressToString(USDC_A),
                        json4,
                        contentExerciseSymbol,
                        json3,
                        // _addressToString(DAI_A),
                        json5
                        // svgAll,
                        // Base64.encode(
                        //     abi.encodePacked(
                        //         svg1,
                        //         contentUnderlyingSymbol,
                        //         svg2,
                        //         contentExerciseSymbol,
                        //         svg3,
                        //         "Long",
                        //         svg4,
                        //         TokenURIGenerator._toString(100e6),
                        //         svg5,
                        //         contentUnderlyingSymbol,
                        //         svg6,
                        //         TokenURIGenerator._toString(20e18),
                        //         svg5,
                        //         contentExerciseSymbol,
                        //         svg8,
                        //         TokenURIGenerator._toString(TIME0),
                        //         svg9,
                        //         TokenURIGenerator._toString(TIME0 + 30 days),
                        //         svg10
                        //     )
                        // ),
                        // json6
                    )
                )
            )
        );

        uint256 optionId = engine.newOptionType({
            underlyingAsset: USDC_A,
            underlyingAmount: 100e6,
            exerciseAsset: DAI_A,
            exerciseAmount: 20e18,
            exerciseTimestamp: TIME0,
            expiryTimestamp: TIME0 + 30 days
        });

        // emit log_named_string("option", optionUri);
        assertEq(engine.uri(optionId), expectedOptionUri);
    }

    // function testTokenURIForClaim() public {
    //     (uint256 optionId, ) = _createNewOptionType({
    //         underlyingAsset: USDC_A,
    //         underlyingAmount: 100,
    //         exerciseAsset: DAI_A,
    //         exerciseAmount: testExerciseAmount,
    //         exerciseTimestamp: testExerciseTimestamp,
    //         expiryTimestamp: testExpiryTimestamp
    //     });

    //     vm.prank(ALICE);
    //     uint256 claimId = engine.write(optionId, 100);
    //     string memory claimUri = engine.uri(claimId);

    //     emit log_named_string("claim", claimUri);
    // }

    function _writeTokenBalance(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(IERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    // TODO not DRY; copied from production code

    bytes16 internal constant ALPHABET = "0123456789abcdef";

    function _addressToString(address addr) internal pure returns (string memory) {
        return _toHexString(uint256(uint160(addr)), 20);
    }

    function _toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = ALPHABET[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        
        return string(buffer);
    }
}
