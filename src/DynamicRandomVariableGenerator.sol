// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./interfaces/IDynamicRandomVariableGenerator.sol";

contract DynamicRandomVariableGenerator is IDynamicRandomVariableGenerator {
    /// @inheritdoc IDynamicRandomVariableGenerator
    function getElements() external view returns (Element[] memory elements) {
        revert();
    }

    /// @inheritdoc IDynamicRandomVariableGenerator
    function generateRandomVariable() external returns (Element memory element) {
        revert();
    }

    /// @inheritdoc IDynamicRandomVariableGenerator
    function updateElementWeight(uint32 elementIndex, uint128 weight) external {
        revert();
    }

}