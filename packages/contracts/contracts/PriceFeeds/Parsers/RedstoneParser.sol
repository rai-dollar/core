// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../Common/TellorCaller.sol";
import "../Interfaces/IPriceFeed.sol";


/*
* this library is used to parse the response from the Tellor oracle and convert it to the Response struct
*/

library RedstoneParser {
    struct RedstoneResponse {
        bool ifRetrieve;
        uint256 value;
        uint256 timestamp;
        bool success;
    }

    function getResponse() public view returns (IPriceFeed.Response memory response) {

    }

    function parseRedstoneResponse(uint256 requestId) internal view returns (IPriceFeed.Response memory response) {

    }
}