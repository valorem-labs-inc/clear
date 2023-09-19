// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Script.sol";

// import "../src/TokenURIGenerator.sol";
import "test/mocks/MockUSDC.sol";
import "test/mocks/MockWETH.sol";
import "test/mocks/MockGMX.sol";

// Salt for mocks

contract DeployMocksScript is Script {
    uint256 constant SALT = 0x2023091301;
    //  Mock USDC Deployed to address: 0x37FeA693DC8C1CeA5244Ca2494762328e56dd959
    //  Mock WETH Deployed to address: 0x1D621b431bF56a3fd49339FF0f9ea9F5B8933C1d
    //  Mock GMX Deployed to address: 0x385Fc55C5E5bAA04c938f85C439a53d9484780cc

    function run() public {
        // Deploy USDC Mock
        vm.startBroadcast(vm.envUint("TEST_MAKER_PK"));
        MockUSDC mockUsdc = new MockUSDC{salt: bytes32(SALT)}();
        console.log("Mock USDC Deployed to address: %s", address(mockUsdc));
        vm.stopBroadcast();

        // Deploy WETH Mock
        vm.startBroadcast(vm.envUint("TEST_MAKER_PK"));
        MockWETH mockWeth = new MockWETH{salt: bytes32(SALT)}();
        console.log("Mock WETH Deployed to address: %s", address(mockWeth));
        vm.stopBroadcast();

        // Deploy GMX Mock
        vm.startBroadcast(vm.envUint("TEST_MAKER_PK"));
        MockGMX mockGmx = new MockGMX{salt: bytes32(SALT)}();
        console.log("Mock GMX Deployed to address: %s", address(mockGmx));
        vm.stopBroadcast();
    }
}
