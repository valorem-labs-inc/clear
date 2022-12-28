// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract ProtocolAdmin is BaseActor {
    address private defaultFeeTo;

    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test) BaseActor(_engine, _test) {
        defaultFeeTo = engine.feeTo();
    }

    function setFeesEnabled(bool enable) external {
        console.logString("setFeesEnabled");
        engine.setFeesEnabled(enable);
    }

    function setFeeTo(bool set, bool accept) external {
        console.logString("setFeeTo");

        if (!set) {
            return;
        }

        address currentFeeTo = engine.feeTo();

        if (address(this) != currentFeeTo) {
            engine.setFeeTo(address(this));
            if (accept) {
                engine.acceptFeeTo();
            }
        } else {
            engine.setFeeTo(defaultFeeTo);
            if (accept) {
                vm.prank(defaultFeeTo);
                engine.acceptFeeTo();
            }
        }
    }

    function sweepFees() external {
        console.logString("sweepFees");
        IERC20[] memory mockErc20s = test.getMockErc20s();
        address[] memory _mockErc20s = new address[](mockErc20s.length);

        for (uint i = 0; i < mockErc20s.length; i++){
            // need to change type from IERC20 to address
            _mockErc20s[i] = address(mockErc20s[i]);
        }

        address _feeTo = engine.feeTo();

        if (_feeTo == address(this)) {
            engine.sweepFees(_mockErc20s);
            return;
        }

        vm.prank(_feeTo);
        engine.sweepFees(_mockErc20s);
    }
}
