// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../Common/LiquityMath.sol";
import {Constants as C} from "../Common/Constants.sol";
import "../Interfaces/IApi3ReaderProxy.sol";
import "../Interfaces/IPriceFeed.sol";

/*
* this library is used to parse the response from the Api3 oracle and convert it to the Response struct
*/


library Api3Parser {

    struct Api3Response {
        int224 value;
        uint32 timestamp;
    }

    function getResponse(address _api3ReaderProxy) internal view returns (IPriceFeed.Response memory response) {
        Api3Response memory api3Response;
        IApi3ReaderProxy api3ReaderProxy = IApi3ReaderProxy(_api3ReaderProxy);

        uint256 gasBefore = gasleft();

        // api3 returns a 18 decimal value
        try api3ReaderProxy.read() returns (int224 value, uint32 timestamp) {
            api3Response.value = value;
            api3Response.timestamp = timestamp;

            uint256 convertedPrice = uint256(int256(api3Response.value));
            response.price = convertedPrice;
            response.lastUpdated = api3Response.timestamp;

            response.success = response.lastUpdated != 0 && response.price != 0;
            return response;
        } catch {
            if (gasleft() <= gasBefore / 64) revert IPriceFeed.InsufficientGasForExternalCall();

            return response;
        }
    }

    function api3StalenessThreshold() internal pure returns (uint256) {
        return C.API3_STALENESS_THRESHOLD;
    }

}