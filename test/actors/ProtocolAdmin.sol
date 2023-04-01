// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract ProtocolAdmin is BaseActor {
    address private defaultFeeTo;

    constructor(ValoremOptionsClearinghouse _clearinghouse, ValoremOptionsClearinghouseInvariantTest _test)
        BaseActor(_clearinghouse, _test)
    {
        defaultFeeTo = clearinghouse.feeTo();
    }

    function setFeesEnabled(bool enable) external {
        console.logString("setFeesEnabled");
        clearinghouse.setFeesEnabled(enable);
    }

    function setFeeTo(bool set, bool accept) external {
        console.logString("setFeeTo");

        if (!set) {
            return;
        }

        address currentFeeTo = clearinghouse.feeTo();

        if (address(this) != currentFeeTo) {
            clearinghouse.setFeeTo(address(this));
            if (accept) {
                clearinghouse.acceptFeeTo();
            }
        } else {
            clearinghouse.setFeeTo(defaultFeeTo);
            if (accept) {
                vm.prank(defaultFeeTo);
                clearinghouse.acceptFeeTo();
            }
        }
    }

    function sweepFees() external {
        console.logString("sweepFees");
        IERC20[] memory mockErc20s = test.getMockErc20s();
        address[] memory _mockErc20s = new address[](mockErc20s.length);

        for (uint256 i = 0; i < mockErc20s.length; i++) {
            // need to change type from IERC20 to address
            _mockErc20s[i] = address(mockErc20s[i]);
        }

        address _feeTo = clearinghouse.feeTo();

        if (_feeTo == address(this)) {
            clearinghouse.sweepFees(_mockErc20s);
            return;
        }

        vm.prank(_feeTo);
        clearinghouse.sweepFees(_mockErc20s);
    }
}
