# Valorem Options V1 Core

## Abstract
This DeFi money lego enables writing covered call and covered put, physically settled, american or european options. All
written options are fully collateralized against an ERC-20 underlying asset and exercised with an ERC-20 exercise asset
on a FIFO written basis per unique option type. Options contracts are issued as ERC-1155 tokens, with each token
representing a contract. Option writers are issued a 1/1 ERC-1155 NFT representing a lot of contracts written for
claiming collateral and exercise assignment. The protocol allows for pluggable premium pricing models for use in
markets.

## On the exercise assignment process

Traditional options are settled in two ways, FIFO or random. Firstly, there is no way to get real or even pseudo random
numbers without reliance on an outside oracle on the blockchain. Secondly, we had considered using a 1/1 ERC-1155 to
represent each individual option and assigning exercise per token. However the gas overhead and other technical
considerations made this impractical, so we went with a FIFO queue on the order the options were written.

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
