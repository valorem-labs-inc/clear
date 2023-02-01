// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2023.
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import {Math} from "../src/utils/Math.sol";
import {DRVUtils} from "../src/utils/DRVUtils.sol";

contract World {
    uint256 public N;
    uint256 public L;
    uint256 public R;
    // Element[] public elements;
    // mapping (uint256 => mapping (uint256 => Range)) public forest; // forest[level][rangeNumber]
    // uint256[] public rangeWeights;
    // uint256[] public levelWeights;

    constructor(uint256 numberOfElements, uint256 numberOfLevels, uint256 numberOfRanges) {
        N = numberOfElements;
        L = numberOfLevels;
        R = numberOfRanges;
    }
}

/// @notice Invariant tests for LibDRV
contract LibDRVTest is Test {
    World internal world;

    function setUp() public {
        world = new World(11, 2, 9);
    }

    /**
     * @dev Invariant G -- "Maximum number of levels"
     *
     * The total number of levels L in the forest of trees is <= lg* N - 1 (where lg* denotes
     * the base-2 iterative logarithm).
     */
    function testG_maximumNumberOfLevels() public {
        assertLe(world.L(), Math.logStar2(world.L()), "Maximum number of levels");
    }

    /**
     * @dev Invariant H -- "Number of non-empty ranges"
     * 
     * // TODO how to accurately assert the value is on the order of N ?
     *
     * The number of non-empty ranges is O(N).
     */
    function testH_numberOfNonEmptyRanges() public {
        assertLe(world.R(), world.N(), "Number of non-empty ranges");
    }

    /**
     * @dev Invariant A -- "Parent range of non-root ranges"
     *
     * For any non-root range R_j_(l) (defined as having degree m >= d, where d is the degree bound
     * constant), its parent range is R_j'_(l+1) and its weight is within [2^(j'-1), 2^(j')),
     * where j' is the range number of its weight.
     */
    function testA_parentRangeOfNonRootRanges() public {
        assertTrue(false, "Parent range of non-root ranges");
    }

    /**
     * @dev Invariant B -- "Difference between range number of children and of non-root range itself"
     *
     * For any non-root range R_j_(l) (defined as having degree m >= d, where d is the degree bound
     * constant), the difference between the range number of its children j' and its own range number j
     * satisfies the inequality lg m - lg (2+b)/(1-b) < j' - j < lg m + lg (2+b)/(1-b).
     */
    function testB_differenceBetweenRangeNumberOfChildrenAndNonRootRangeItself() public {
        assertTrue(false, "Difference between range number of children and of non-root range itself");        
    }

    /**
     * @dev Invariant C -- "Degree of one child of non-root ranges on level 2+"
     * 
     * // TODO clarify if is this one child and one child only, or at least one child (from Lemma 2')
     *
     * For any non-root range R_j_(l) (defined as having degree m >= d, where d is the degree bound
     * constant) on level 2 or higher, one of its children has degree >= 2^(m-1+c), where c is a 
     * non-negative integer constant >= 1 used to calculate the degree bound constant.
     */
    function testC_degreeOfOneChildOfNonRootRangesOnLevel2AndUp() public {
        assertTrue(false, "Degree of one child of non-root ranges on level 2+");
    }

    /**
     * @dev Invariant D -- "Number of grandchildren of non-root ranges on level 2+"
     *
     * For any non-root range R_j_(l) (defined as having degree m >= d, where d is the degree bound
     * constant) on level 2 or higher, the number of its grandchildren is >= 2^(m+c) - 2^c + m, where
     * c is a non-negative integer constant >= 1 used to calculate the degree bound constant.
     */
    function testD_numberOfGrandchildrenOfNonRootRangesOnLevel2AndUp() public {
        assertTrue(false, "Number of grandchildren of non-root ranges on level 2+");        
    }

    /**
     * @dev Invariant E -- "Difference between range numbers of smallest-numbered descendents of non-root ranges on level 3+"
     * 
     * // TODO what precisely is smallest-numbered range? —- think smallest index but could be smallest weight / range number
     *
     * For any non-root range R_j_(l) (defined as having degree m >= d, where d is the degree bound
     * constant) where level l >= k >= 3, the range number of the smallest-numbered descendent range
     * on level l-k minus the range number of the smallest-numbered descendent range on level l-k+1
     * is greater than the base-2 power tower of order k and hat m (e.g., the base-2 power tower of
     * order 3 and hat m is 2^2^2^m, for order 4 it is 2^2^2^2^m, etc.).
     */
    function testE_differenceBetweenRangeNumbersOfSmallestNumberedDescendentsOfNonRootRangesOnLevel3AndUp() public {
        assertTrue(false, "Difference between range numbers of smallest-numbered descendents of non-root ranges on level 3+");        
    }

    /**
     * @dev Invariant F -- "Number of descendents of non-root ranges on level 3+"
     *
     * For any non-root range R_j_(l) (defined as having degree m >= d, where d is the degree bound
     * constant) where level l >= k >= 3, the number of descendents on level l-k > the base-2 power
     * tower of order k and hat m (see Invariant E for power tower examples).
     */
    function testF_numberOfDescendentsOfNonRootRangesOnLevel3AndUp() public {
        assertTrue(false, "Number of descendents of non-root ranges on level 3+");        
    }
}
