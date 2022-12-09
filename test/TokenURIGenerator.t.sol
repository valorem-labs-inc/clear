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

    struct StringFragments {
        string jsonStart;
        string jsonName;
        string jsonDescription;
        string jsonDescription2;
        string jsonDescription3;
        string jsonImage;
        string jsonEnd;
        string svgStart;
        string svg2;
        string svg3;
        string svg4;
        string svg5;
        string svg6;
        string svg7;
        string svg8;
        string svgEnd;
    }

    struct OptionContent {
        string optionShortcode;
        string optionType;
        string underlyingSymbol;
        string exerciseSymbol;
    }

    function testTokenURIForOption() public {
        OptionContent memory content = OptionContent({
            optionShortcode: "USDCDAI220622C",
            optionType: "Long",
            underlyingSymbol: "USDC",
            exerciseSymbol: "DAI"
        });

        StringFragments memory fragments = StringFragments({
            jsonStart: "data:application/json;base64,",
            jsonName: '{"name":"',
            jsonDescription: '", "description": "NFT representing a Valorem options contract. ',
            jsonDescription2: " Address: ",
            jsonDescription3: ". ",
            jsonImage: ' .", "image": "data:image/svg+xml;base64,',
            jsonEnd: '"}',
            svgStart: "<svg width='400' height='300' viewBox='0 0 400 300' xmlns='http://www.w3.org/2000/svg'><rect width='100%' height='100%' rx='12' ry='12'  fill='#3E5DC7' /><g transform='scale(5), translate(25, 18)' fill-opacity='0.15'><path xmlns='http://www.w3.org/2000/svg' d='M69.3577 14.5031H29.7265L39.6312 0H0L19.8156 29L29.7265 14.5031L39.6312 29H19.8156H0L19.8156 58L39.6312 29L49.5421 43.5031L69.3577 14.5031Z' fill='white'/></g><text x='16px' y='55px' font-size='32px' fill='#fff' font-family='Helvetica'>",
            svg2: " / ",
            svg3: "</text><text x='16px' y='80px' font-size='16' fill='#fff' font-family='Helvetica' font-weight='300'>",
            svg4: " Call</text><text x='16px' y='116px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>UNDERLYING ASSET</text><text x='16px' y='140px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>",
            svg5: " ",
            svg6: "</text><text x='16px' y='176px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>EXERCISE ASSET</text><text x='16px' y='200px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>",
            svg7: "</text><text x='16px' y='236px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>EXERCISE DATE</text><text x='16px' y='260px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>",
            svg8: "</text><text x='200px' y='236px' font-size='14' letter-spacing='0.01em' fill='#fff' font-family='Helvetica'>EXPIRY DATE</text><text x='200px' y='260px' font-size='18' fill='#fff' font-family='Helvetica' font-weight='300'>",
            svgEnd: "</text></svg>"
        });

        string memory expectedOptionUri = string(
            abi.encodePacked(
                fragments.jsonStart,
                Base64.encode(
                    abi.encodePacked(
                        fragments.jsonName,
                        content.optionShortcode,
                        fragments.jsonDescription,
                        content.underlyingSymbol,
                        fragments.jsonDescription2,
                        addressToString(USDC_A),
                        fragments.jsonDescription3,
                        content.exerciseSymbol,
                        fragments.jsonDescription2
                        // addressToString(DAI_A)
                        // fragments.jsonImage
                        // Base64.encode(
                        //     abi.encodePacked(
                        //         fragments.svgStart,
                        //         content.underlyingSymbol,
                        //         fragments.svg2,
                        //         content.exerciseSymbol,
                        //         fragments.svg3,
                        //         content.optionType,
                        //         fragments.svg4,
                        //         uintToString(100e6),
                        //         fragments.svg5,
                        //         content.underlyingSymbol,
                        //         fragments.svg6,
                        //         uintToString(20e18),
                        //         fragments.svg5,
                        //         content.exerciseSymbol,
                        //         fragments.svg7,
                        //         uintToString(TIME0),
                        //         fragments.svg8,
                        //         uintToString(TIME0 + 30 days),
                        //         fragments.svgEnd
                        //     )
                        // ),
                        // fragments.jsonEnd
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

    bytes1 internal constant DOUBLE_QUOTE = '"';
    bytes16 internal constant ALPHABET = "0123456789abcdef";

    // From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol#L16
    function uintToString(uint256 value) internal pure returns (string memory) {        
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    function escapeQuotes(string memory symbol) internal pure returns (string memory) {
        bytes memory symbolBytes = bytes(symbol);
        uint8 quotesCount = 0;
        for (uint8 i = 0; i < symbolBytes.length; i++) {
            // solhint-disable quotes
            if (symbolBytes[i] == DOUBLE_QUOTE) {
                quotesCount++;
            }
        }
        if (quotesCount > 0) {
            bytes memory escapedBytes = new bytes(
                symbolBytes.length + (quotesCount)
            );
            uint256 index;
            for (uint8 i = 0; i < symbolBytes.length; i++) {
                // solhint-disable quotes
                if (symbolBytes[i] == DOUBLE_QUOTE) {
                    escapedBytes[index++] = "\\";
                }
                escapedBytes[index++] = symbolBytes[i];
            }
            return string(escapedBytes);
        }

        return symbol;
    }

    function addressToString(address addr) internal pure returns (string memory) {
        uint256 value = uint256(uint160(addr));
        uint256 length = 20;

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
