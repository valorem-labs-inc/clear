// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022
pragma solidity 0.8.16;

/**
 * @notice An interface for a random variable uniformly distributed over
 * the half open range supplied.
 */
interface IUniformRandom {
    /**
     * @notice Gets a uniformly distributed random value >= gte and < lt.
     * @param gte The value which the random variable will be greater than or equal to.
     * @param lt The value which the random varaibale will be less than.
     * @return val The random variable uniformly distributed in [gte, lt).
     */
    function getRandom(uint256 gte, uint256 lt) returns(uint256 val);
}