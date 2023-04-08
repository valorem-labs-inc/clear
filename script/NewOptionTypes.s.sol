// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {IValoremOptionsClearinghouse} from "../src/interfaces/IValoremOptionsClearinghouse.sol";

contract NewOptionTypes is Script {
    // Command to run this script:
    // $ forge script script/NewOptionTypes.s.sol --rpc-url=$RPC --broadcast

    IValoremOptionsClearinghouse internal constant clearinghouse =
        IValoremOptionsClearinghouse(0x7513F78472606625A9B505912e3C80762f6C9Efb);

    address internal constant WETH = 0xe39Ab88f8A4777030A534146A9Ca3B52bd5D43A3;
    uint96[] internal WETH_STRIKES;
    address internal constant WBTC = 0xf8Fe24D6Ea205dd5057aD2e5FE5e313AeFd52f2e;
    uint96[] internal WBTC_STRIKES;
    address internal constant GMX = 0x5337deF26Da2506e08e37682b0d6E50b26a704BB;
    uint96[] internal GMX_STRIKES;
    address internal constant MAGIC = 0xb795f8278458443f6C43806C020a84EB5109403c;
    uint96[] internal MAGIC_STRIKES;
    address internal constant LUSD = 0x42dED0b3d65510B5d1857bF26466b3b0b9e0BbbA;

    uint40[] internal EXPIRIES;

    function run() public {
        // Get environment variables.
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Get timestamp.
        uint40 goodFriday = 1680883200; // Fri Apr 07 2023 16:00:00 GMT+0000

        // Setup strikes.
        WETH_STRIKES = new uint96[](5);
        WETH_STRIKES[0] = 1_700 ether;
        WETH_STRIKES[1] = 1_750 ether;
        WETH_STRIKES[2] = 1_800 ether;
        WETH_STRIKES[3] = 1_850 ether;
        WETH_STRIKES[4] = 1_900 ether;

        WBTC_STRIKES = new uint96[](5);
        WBTC_STRIKES[0] = 27_000 ether;
        WBTC_STRIKES[1] = 27_500 ether;
        WBTC_STRIKES[2] = 28_000 ether;
        WBTC_STRIKES[3] = 28_500 ether;
        WBTC_STRIKES[4] = 29_000 ether;

        GMX_STRIKES = new uint96[](5);
        GMX_STRIKES[0] = 70 ether;
        GMX_STRIKES[1] = 75 ether;
        GMX_STRIKES[2] = 80 ether;
        GMX_STRIKES[3] = 85 ether;
        GMX_STRIKES[4] = 90 ether;

        MAGIC_STRIKES = new uint96[](5);
        MAGIC_STRIKES[0] = 0.5 ether;
        MAGIC_STRIKES[1] = 1.0 ether;
        MAGIC_STRIKES[2] = 1.5 ether;
        MAGIC_STRIKES[3] = 2.0 ether;
        MAGIC_STRIKES[4] = 2.5 ether;

        // Setup expiries.
        EXPIRIES = new uint40[](4);
        EXPIRIES[0] = goodFriday + 1 weeks;
        EXPIRIES[1] = goodFriday + 2 weeks;
        EXPIRIES[2] = goodFriday + 3 weeks;
        EXPIRIES[3] = goodFriday + 4 weeks;

        vm.startBroadcast(privateKey);
        for (uint256 j = 0; j < EXPIRIES.length; j++) {
            // Create new option types for WETH.
            for (uint256 i = 0; i < WETH_STRIKES.length; i++) {
                // Create new Call option type.
                clearinghouse.newOptionType({
                    underlyingAsset: WETH,
                    underlyingAmount: 1 ether,
                    exerciseAsset: LUSD,
                    exerciseAmount: WETH_STRIKES[i],
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });

                // Create new Put option type.
                clearinghouse.newOptionType({
                    underlyingAsset: LUSD,
                    underlyingAmount: WETH_STRIKES[i],
                    exerciseAsset: WETH,
                    exerciseAmount: 1 ether,
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });
            }

            // Create new option types for WBTC.
            for (uint256 i = 0; i < WBTC_STRIKES.length; i++) {
                // Create new Call option type.
                clearinghouse.newOptionType({
                    underlyingAsset: WBTC,
                    underlyingAmount: 1e8,
                    exerciseAsset: LUSD,
                    exerciseAmount: WBTC_STRIKES[i],
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });

                // Create new Put option type.
                clearinghouse.newOptionType({
                    underlyingAsset: LUSD,
                    underlyingAmount: WBTC_STRIKES[i],
                    exerciseAsset: WBTC,
                    exerciseAmount: 1e8,
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });
            }

            // Create new option types for GMX.
            for (uint256 i = 0; i < GMX_STRIKES.length; i++) {
                // Create new Call option type.
                clearinghouse.newOptionType({
                    underlyingAsset: GMX,
                    underlyingAmount: 1 ether,
                    exerciseAsset: LUSD,
                    exerciseAmount: GMX_STRIKES[i],
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });

                // Create new Put option type.
                clearinghouse.newOptionType({
                    underlyingAsset: LUSD,
                    underlyingAmount: GMX_STRIKES[i],
                    exerciseAsset: GMX,
                    exerciseAmount: 1 ether,
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });
            }

            // Create new option types for MAGIC.
            for (uint256 i = 0; i < MAGIC_STRIKES.length; i++) {
                // Create new Call option type.
                clearinghouse.newOptionType({
                    underlyingAsset: MAGIC,
                    underlyingAmount: 1 ether,
                    exerciseAsset: LUSD,
                    exerciseAmount: MAGIC_STRIKES[i],
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });

                // Create new Put option type.
                clearinghouse.newOptionType({
                    underlyingAsset: LUSD,
                    underlyingAmount: MAGIC_STRIKES[i],
                    exerciseAsset: MAGIC,
                    exerciseAmount: 1 ether,
                    exerciseTimestamp: goodFriday,
                    expiryTimestamp: EXPIRIES[j]
                });
            }
        }
        vm.stopBroadcast();
    }
}
