// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

library QueueLib {
    error EmptyQueue();

    struct Queue {
        mapping(uint256 => bytes32) _queue;
        uint256 _first;
        uint256 _last;
    }

    function init(Queue storage queue) internal {
        queue._first = 1;
        queue._last = 0;
    }

    function size(Queue storage queue) internal view returns (uint256) {
        return queue._last;
    }

    function enqueue(Queue storage queue, bytes32 element) internal {
        queue._last++;
        queue._queue[queue._last] = element;
    }

    function dequeue(Queue storage queue) internal returns (bytes32 element) {
        if (queue._last < queue._first) {
            revert EmptyQueue();
        }

        element = queue._queue[queue._first];
        delete queue._queue[queue._first];
        queue._first++;
    }
}
