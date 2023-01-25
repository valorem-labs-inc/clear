// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022
pragma solidity 0.8.16;

/**
 * @notice Defines the interface for a generator of random variables, selecting from
 * a range of elements, with a dynamically weighted probability distribution function. 
 */
interface IDynamicRandomVariableGenerator {

    /*//////////////////////////////////////////////////////////////
    //  Data Structures
    //////////////////////////////////////////////////////////////*/

    /// @notice An element that can be selected from many, with liklihood 
    /// of selection dictated by its weight.
    struct Element {
        uint32 index;
        uint128 weight;
    }

    /*//////////////////////////////////////////////////////////////
    //  Views
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the list of elements maintained by the dynamic random 
     * variable generator.
     * @return elements An array of elements maintained by the drv generator.
     */
    function getElements() external view returns (Element[] memory elements);

    /**
     * @notice Generates a random variable, returning an element with weighted liklihood
     * @dev Can potentially consume entropy; not a view.
     * @return element The randomly seleted element.
     */
    function generateRandomVariable() external returns (Element memory element);

    /**
     * @notice Updates the weight of a particular element in the list
     * @param elementIndex The index of the element to weight.
     * @param weight The absolute weight of the supplied element index.
     */
    function updateElementWeight(uint32 elementIndex, uint128 weight) external;
   }
