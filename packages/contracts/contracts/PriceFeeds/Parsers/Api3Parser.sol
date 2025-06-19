// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/LiquityMath.sol";
import "./Structs.sol";

/*
* this library is used to parse the response from the Api3 oracle and convert it to the Response struct
*/

interface IApi3ReaderProxy {
    function read() external view returns (int224 value, uint32 timestamp);
}

library Api3Response {
    struct Api3Response {
        int224 value;
        uint32 timestamp;
    }
    function getApi3Response(address api3ReaderProxy) internal view returns (Response memory) {
        Api3Response memory response;
        // api3 returns a 18 decimal value
        (response.value, response.timestamp) = IApi3ReaderProxy(api3ReaderProxy).read();
        return Response({price: response.value, lastUpdated: response.timestamp});
    }


}