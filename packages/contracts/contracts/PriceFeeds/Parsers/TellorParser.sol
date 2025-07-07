// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../Interfaces/IPriceFeed.sol";
import {Constants as C} from "../Common/Constants.sol";
import {ITellor} from "../Interfaces/ITellor.sol";

/*
* this library is used to parse the response from the Tellor oracle and convert it to the Response struct
*/

library TellorParser {
    struct TellorResponse {
        bool ifRetrieve;
        bytes data;
        uint256 timestamp;
    }
    function getResponse(address _tellorOracle, bytes32 _queryId, uint256 stalenessThreshold) internal view returns (IPriceFeed.Response memory response) {
        ITellor tellor = ITellor(_tellorOracle);
        TellorResponse memory tellorResponse;

        uint256 gasBefore = gasleft();

        try tellor.getDataBefore(_queryId, block.timestamp - stalenessThreshold) returns (bool ifRetrieve, bytes memory data, uint256 timestampRetrieved) {
            tellorResponse.ifRetrieve = ifRetrieve;
            tellorResponse.data = data;
            tellorResponse.timestamp = timestampRetrieved;
            
        } catch {
            // Require that enough gas was provided to prevent an OOG revert in the call to Chainlink
            // causing a shutdown. Instead, just revert. Slightly conservative, as it includes gas used
            // in the check itself.
            if (gasleft() <= gasBefore / 64) revert IPriceFeed.InsufficientGasForExternalCall();


            return response;
        }

        
        response.price = abi.decode(tellorResponse.data, (uint256));
        response.lastUpdated = tellorResponse.timestamp;
        response.success = response.lastUpdated != 0 && response.price != 0;
        
        return response;
    }


}