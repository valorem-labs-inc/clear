# Valorem Options V1 Core

## Abstract

Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, american or
european options. All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
ERC-20 exercise asset using a deterministic algorithm for fair settlement. Options contracts
are issued as fungible ERC-1155 tokens, with each token representing a contract. Option writers are additionally issued
an ERC-1155 NFT representing a lot of contracts written for claiming collateral and exercise assignment. This design
eliminates the need for market price oracles, and allows for permission-less writing, and gas efficient transfer, of
a broad swath of traditional options.

## Disclaimer

This project is Alpha quality at present, and interfaces are subject to change.