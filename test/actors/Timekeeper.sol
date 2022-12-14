// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import {CommonBase} from "forge-std/Common.sol";

/// @dev Father Time warps forward a random number of days and blocks
contract Timekeeper is CommonBase {
    function tickTock(uint8 numDays, uint16 numBlocks) external {
        vm.warp(block.timestamp + uint256(numDays) * 1 days);
        vm.roll(block.number + numBlocks);
    }
}
