// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./Dependencies/AggregatorV3Interface.sol";
import "./Dependencies/LiquityMath.sol";
import "./Structs.sol";

/*
* this library is used to parse the response from the Chainlink oracle and convert it to the Response struct
*/

library ChainlinkParser {
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    function getChainlinkResponse(address chainlinkOracle) internal pure returns (Response memory) {
        ChainlinkResponse memory response;
        (response.roundId, response.answer, response.startedAt, response.updatedAt, response.answeredInRound) = AggregatorV3Interface(chainlinkOracle).latestRoundData();
        uint256 convertedPrice = convertDecimals(response.answer, AggregatorV3Interface(chainlinkOracle).decimals());
        return Response({price: convertedPrice, lastUpdated: response.updatedAt});
    }

    function convertDecimals(uint256 price, uint8 decimals) internal pure returns (uint256) {
        return price * 10 ** (18 - decimals);
    }
}