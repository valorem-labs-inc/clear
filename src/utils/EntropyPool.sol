// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./Queue.sol";

// TODO
library EntropyPoolLib {
    uint16 private constant MAX_ELEMENTS = 2_048;

    struct EntropyPool {
        QueueLib.Queue _queue;
    }

    function checkEntropy(EntropyPool storage entropyPool) internal view returns (uint256 queueSize) {
        queueSize = QueueLib.size(entropyPool._queue);
    }

    function seedEntropy(EntropyPool storage entropyPool) internal {
        QueueLib.init(entropyPool._queue);
        for (uint256 i = 1; i <= 256; i++) {
            EntropyPoolLib.recordEntropy(entropyPool, keccak256(abi.encode(msg.sender, blockhash(block.number - i))));
        }
    }

    function useEntropy(EntropyPool storage entropyPool) internal returns (bytes32 entropicElement) {
        entropicElement = QueueLib.dequeue(entropyPool._queue);
    }

    function recordEntropy(EntropyPool storage entropyPool, bytes32 entropicElement) internal {
        if (QueueLib.size(entropyPool._queue) < MAX_ELEMENTS) {
            QueueLib.enqueue(entropyPool._queue, entropicElement);
        }
    }
}
