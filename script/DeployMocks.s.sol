// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
//
// Deploys mock ERC20 tokens USDC, WETH, GMX, and WBTC for testing
//
// Can be used with forge: forge script script/DeployMocks.s.sol --rpc-url=<rpc_url> --broadcast --slow --verifier-url=<block_explorer_url> --etherscan-api-key=<block_explorer_key> --verify
//   (requires environment variable TEST_DEPLOYER_PK to be set)
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import "test/mocks/MockUSDC.sol";
import "test/mocks/MockWETH.sol";
import "test/mocks/MockGMX.sol";
import "test/mocks/MockWBTC.sol";

contract DeployMocksScript is Script {
    uint256 constant SALT = 0x2023091301;
    //  Mock USDC Deployed to address: 0x37FeA693DC8C1CeA5244Ca2494762328e56dd959
    //  Mock WETH Deployed to address: 0x1D621b431bF56a3fd49339FF0f9ea9F5B8933C1d
    //  Mock GMX Deployed to address: 0x385Fc55C5E5bAA04c938f85C439a53d9484780cc
    //  Mock WBTC Deployed to address: 0x88109802Af6eB7D9499B1289baa88e1429eA655E

    function run() public {
        // Deploy USDC Mock
        vm.startBroadcast(vm.envUint("TEST_DEPLOYER_PK"));
        MockUSDC mockUsdc = new MockUSDC{salt: bytes32(SALT)}();
        console.log("Mock USDC Deployed to address: %s", address(mockUsdc));
        vm.stopBroadcast();

        // Deploy WETH Mock
        vm.startBroadcast(vm.envUint("TEST_DEPLOYER_PK"));
        MockWETH mockWeth = new MockWETH{salt: bytes32(SALT)}();
        console.log("Mock WETH Deployed to address: %s", address(mockWeth));
        vm.stopBroadcast();

        // Deploy GMX Mock
        vm.startBroadcast(vm.envUint("TEST_DEPLOYER_PK"));
        MockGMX mockGmx = new MockGMX{salt: bytes32(SALT)}();
        console.log("Mock GMX Deployed to address: %s", address(mockGmx));
        vm.stopBroadcast();

        // Deploy WBTC Mock
        vm.startBroadcast(vm.envUint("TEST_DEPLOYER_PK"));
        MockWBTC mockWbtc = new MockWBTC{salt: bytes32(SALT)}();
        console.log("Mock WBTC Deployed to address: %s", address(mockWbtc));
        vm.stopBroadcast();
    }
}
