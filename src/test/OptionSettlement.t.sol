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

        // Now we have 1B DAI
        writeTokenBalance(address(this), wethAddress, 1000000000 * 1e18);
        // And 10 M WETH
        writeTokenBalance(address(this), wethAddress, 10000000 * 1e18);

        // Issue approvals
        weth.approve(address(engine), type(uint256).max);
        dai.approve(address(engine), type(uint256).max);
    }
}
