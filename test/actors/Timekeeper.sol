// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import {CommonBase} from "forge-std/Common.sol";

/// @dev Father Time warps forward a random number of days and blocks
contract Timekeeper is CommonBase {
    function tickTock(uint16 numSeconds, uint16 numBlocks) external {
        vm.warp(block.timestamp + numSeconds);
        vm.roll(block.number + numBlocks);
    }
}
