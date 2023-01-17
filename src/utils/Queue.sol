// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

contract Queue {
    error EmptyQueue();

    mapping(uint256 => bytes32) private queue;
    uint256 private first = 1;
    uint256 private last = 0;

    function size() public view returns (uint256) {
        return last;
    }

    function enqueue(bytes32 element) public {
        last++;
        queue[last] = element;
    }

    function dequeue() public returns (bytes32 element) {
        if (last < first) {
            revert EmptyQueue();
        }

        element = queue[first];
        delete queue[first];
        first++;
    }
}
