// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Script.sol";

import {MockWBTC} from "../test/mocks/MockWBTC.sol";
import {MockGMX} from "../test/mocks/MockGMX.sol";
import {MockMAGIC} from "../test/mocks/MockMAGIC.sol";
import {MockLUSD} from "../test/mocks/MockLUSD.sol";

contract DeployScript is Script {
    // Commands to deploy:
    // $ forge script script/MockTokens.s.sol --rpc-url=$RPC --broadcast
    // y no work $ forge script script/MockTokens.s.sol --rpc-url=$RPC --broadcast --slow --verify "$ARBISCAN_API_KEY" --chain-id=421613 --watch

    // $ forge verify-contract ADDRESS test/mocks/MockWBTC.sol:MockWBTC --etherscan-api-key $ARBISCAN_API_KEY --compiler-version "v0.8.16+commit.07a7930e"  --chain-id=421613 --watch
    // $ forge verify-contract ADDRESS test/mocks/MockGMX.sol:MockGMX --etherscan-api-key $ARBISCAN_API_KEY --compiler-version "v0.8.16+commit.07a7930e"  --chain-id=421613 --watch
    // $ forge verify-contract ADDRESS test/mocks/MockMAGIC.sol:MockMAGIC --etherscan-api-key $ARBISCAN_API_KEY --compiler-version "v0.8.16+commit.07a7930e"  --chain-id=421613 --watch
    // $ forge verify-contract ADDRESS test/mocks/MockLUSD.sol:MockLUSD --etherscan-api-key $ARBISCAN_API_KEY --compiler-version "v0.8.16+commit.07a7930e"  --chain-id=421613 --watch

    function run() public {
        // Get environment variables.
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Deploy mock tokens.
        vm.startBroadcast(privateKey);
        new MockWBTC();
        new MockGMX();
        new MockMAGIC();
        new MockLUSD();
        vm.stopBroadcast();
    }
}
