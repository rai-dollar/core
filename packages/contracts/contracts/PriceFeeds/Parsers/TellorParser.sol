// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../Common/TellorCaller.sol";
import "../Interfaces/IPriceFeed.sol";


/*
* this library is used to parse the response from the Tellor oracle and convert it to the Response struct
*/

library TellorParser {
    struct TellorResponse {
        bool ifRetrieve;
        uint256 value;
        uint256 timestamp;
        bool success;
    }
    function getResponse() public view returns (IPriceFeed.Response memory response) {
    }

    function isStale(uint256 lastUpdated) public view returns (bool) {
        return block.timestamp - lastUpdated > C.TELLOR_STALENESS_THRESHOLD;
    }

    function isGoodResponse(IPriceFeed.Response memory _response) public view returns (bool) {
        return _response.success && _response.price > 0 && _response.lastUpdated > 0 && !isStale(_response.lastUpdated);
    }

}