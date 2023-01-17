// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../src/utils/Queue.sol";

contract QueueTest is Test {
    Queue private queue;

    bytes32[] private elements;

    function setUp() public {
        queue = new Queue();

        elements = new bytes32[](15);
        elements[0] = keccak256(bytes("too many secrets"));
        elements[1] = keccak256(bytes("setec astronomy"));
        elements[2] = keccak256(bytes("cray tomes on set"));
        elements[3] = keccak256(bytes("o no my tesseract"));
        elements[4] = keccak256(bytes("ye some contrast"));
        elements[5] = keccak256(bytes("a tron ecosystem"));
        elements[6] = keccak256(bytes("stonecasty rome"));
        elements[7] = keccak256(bytes("coy teamster son"));
        elements[8] = keccak256(bytes("cyanometer toss"));
        elements[9] = keccak256(bytes("cementatory sos"));
        elements[10] = keccak256(bytes("my cotoneasters"));
        elements[11] = keccak256(bytes("ny sec stateroom"));
        elements[12] = keccak256(bytes("oc attorney mess"));
        elements[13] = keccak256(bytes("my cots earstones"));
        elements[14] = keccak256(bytes("easternmost coy"));
    }

    function test_size() public {
        assertEq(queue.size(), 0, "initial size");

        queue.enqueue(keccak256(bytes("42")));
        assertEq(queue.size(), 1, "size after 1");

        for (uint256 i = 0; i < elements.length; i++) {
            queue.enqueue(elements[i]);
        }

        assertEq(queue.size(), elements.length + 1, "size after enqueueing many");
    }

    function test_enqueue_dequeue() public {
        queue.enqueue(keccak256(bytes("42")));

        assertEq(queue.dequeue(), keccak256(bytes("42")), "dequeue after 1");

        for (uint256 i = 0; i < elements.length; i++) {
            queue.enqueue(elements[i]);
        }

        for (uint256 i = 0; i < elements.length; i++) {
            bytes32 element = elements[i];
            assertEq(queue.dequeue(), element, "dequeue after enqueueing many");
        }
    }

    function testRevert_dequeue_whenEmptyQueue() public {
        vm.expectRevert(Queue.EmptyQueue.selector);

        queue.dequeue();
    }
}
