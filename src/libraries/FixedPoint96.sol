// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
