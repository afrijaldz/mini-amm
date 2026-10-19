// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MiniPair} from "./MiniPair.sol";

/// One pair per token pair. Uniswap uses CREATE2 so the router can compute pair addresses;
/// here the router just reads this mapping.
contract MiniFactory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair);

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "MiniFactory: IDENTICAL_ADDRESSES");
        require(getPair[tokenA][tokenB] == address(0), "MiniFactory: PAIR_EXISTS");

        MiniPair newPair = new MiniPair(tokenA, tokenB);
        pair = address(newPair);
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);
        emit PairCreated(newPair.token0(), newPair.token1(), pair);
    }
}
