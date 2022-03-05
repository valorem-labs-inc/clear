# Valorem Options V1 Core

## Abstract

Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, american or
european options. All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
ERC-20 exercise asset using a chainlink VRF random number per unique option type for fair settlement. Options contracts
are issued as fungible ERC-1155 tokens, with each token representing a contract. Option writers are additionally issued
an ERC-1155 NFT representing a lot of contracts written for claiming collateral and exercise assignment. This design
eliminates the need for market price oracles, and allows for permission-less writing, and gas efficient transfer, of
a broad swath of traditional options.

### FIFO Implementation

https://eips.ethereum.org/EIPS/eip-3529
https://programtheblockchain.com/posts/2018/03/23/storage-patterns-stacks-queues-and-deques/

## About the tokens

https://github.com/solidstate-network/solidstate-solidity/blob/5a8c6745d85b3f39f8f05bcbc5b5a78e7189b216/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol

The options tokens are an IERC1155Enumerable based token. The question at the moment is if the claims and the options
should

## Contract Architecture

Each Option will have an option type and Option Parameters struct as well as an associated option token ID generated
from the hash of that information (collision detection?)
