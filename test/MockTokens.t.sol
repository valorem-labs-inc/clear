// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import {MockWBTC} from "./mocks/MockWBTC.sol";
import {MockGMX} from "./mocks/MockGMX.sol";
import {MockMAGIC} from "./mocks/MockMAGIC.sol";
import {MockLUSD} from "./mocks/MockLUSD.sol";

/// @notice Unit tests for Mock ERC20 tokens
contract MockTokens is Test {
    MockWBTC internal wbtc;
    MockGMX internal gmx;
    MockMAGIC internal magic;
    MockLUSD internal lusd;

    function setUp() public {
        wbtc = new MockWBTC();
        gmx = new MockGMX();
        magic = new MockMAGIC();
        lusd = new MockLUSD();
    }

    function test_WBTC() public {
        assertEq(wbtc.name(), "Wrapped BTC");
        assertEq(wbtc.symbol(), "WBTC");
        assertEq(wbtc.decimals(), 8);
    }

    function test_GMX() public {
        assertEq(gmx.name(), "GMX");
        assertEq(gmx.symbol(), "GMX");
        assertEq(gmx.decimals(), 18);
    }

    function test_MAGIC() public {
        assertEq(magic.name(), "MAGIC");
        assertEq(magic.symbol(), "MAGIC");
        assertEq(magic.decimals(), 18);
    }

    function test_LUSD() public {
        lusd = new MockLUSD();
        assertEq(lusd.name(), "LUSD Stablecoin");
        assertEq(lusd.symbol(), "LUSD");
        assertEq(lusd.decimals(), 18);
    }
}
