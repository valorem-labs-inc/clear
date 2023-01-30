// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../src/utils/Math.sol";

contract World {
    uint256 public N;
    uint256 public L;

    constructor(uint256 numberOfElements, uint256 numberOfLevels) {
        N = numberOfElements;
        L = numberOfLevels;
    }
}

/// @notice Invariant tests for LibDRV
contract LibDRVTest is Test {
    World internal world;

    function setUp() public {
        world = new World(11, 2);
    }

    /**
     * @dev Invariant T4.G -- "Maximum number of levels"
     *
     * L <= log*N - 1
     */
    function test_maximumNumberOfLevels() public {
        assertEq(world.L(), 2, "maximum number of levels");
    }
}
