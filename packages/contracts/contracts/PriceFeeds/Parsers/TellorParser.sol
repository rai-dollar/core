// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./Structs.sol";
import "./Dependencies/TellorCaller.sol";

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
    function parseTellorResponse(TellorResponse memory response) internal pure returns (Response memory) {
        return Response({price: response.value, timestamp: response.timestamp, success: response.success});
    }
}