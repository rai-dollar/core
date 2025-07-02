// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../../PriceFeeds/Interfaces/IApi3ReaderProxy.sol";

contract MockApi3Aggregator is IApi3ReaderProxy {
    
    // storage variables to hold the mock data
    uint8 private decimalsVal = 18;
    int224 private price;
    uint32 private updateTime;

    bool latestRevert;
    bool decimalsRevert;

    // --- Functions ---

    function setDecimals(uint8 _decimals) external {
        decimalsVal = _decimals;
    }

    function setPrice(int224 _price) external {
        price = _price;
    }


    function setUpdateTime(uint32 _updateTime) external  {
        updateTime = _updateTime;
    }
    

    // --- Getters that adhere to the AggregatorV3 interface ---

    function decimals() external override view returns (uint8) {
        if (decimalsRevert) {require(1== 0, "decimals reverted");}

        return decimalsVal;
    }

    function read()
        external
        view
    returns (
        int224 value,
        uint32 timestamp
    ) 
    {    
        if (latestRevert) { require(1== 0, "read reverted");}

        return (price, updateTime); 
    }

}
