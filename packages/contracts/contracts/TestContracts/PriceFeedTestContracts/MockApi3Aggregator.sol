// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../../PriceFeeds/Interfaces/IApi3ReaderProxy.sol";

contract MockApi3Aggregator is IApi3ReaderProxy {
    
    // storage variables to hold the mock data
    uint8 public decimalsVal = 18;
    int224 public price;
    uint32 public updateTime;

    bool revertRead;
    bool decimalsRevert;

    event PriceEmitted(int224 price, uint32 updateTime);
    // --- Functions ---

    function setDecimals(uint8 _decimals) external {
        decimalsVal = _decimals;
    }

    function setPrice(int224 _price) external {
        price = _price;
    }

    function setReadRevert(bool _revert) external {
        revertRead = _revert;
    }

    function setDecimalsRevert(bool _revert) external {
        decimalsRevert = _revert;
    }

    function setTime(uint32 _updateTime) external  {
        updateTime = _updateTime;
    }
    

    // --- Getters that adhere to the AggregatorV3 interface ---

    function decimals() external override view returns (uint8) {
        if (decimalsRevert) {revert("decimals reverted");}

        return decimalsVal;
    }

    function emitPrice() external {
        emit PriceEmitted(price, updateTime);
    }

    function read()
        external
        view
    returns (
        int224 value,
        uint32 timestamp
    ) 
    {    
        if (revertRead) { revert("read reverted");}

        return (price, updateTime); 
    }

}
