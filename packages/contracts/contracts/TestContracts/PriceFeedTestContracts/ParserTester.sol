// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../../PriceFeeds/PriceFeedBase.sol";
import "../../PriceFeeds/Parsers/ChainlinkParser.sol";
import "../../PriceFeeds/Parsers/Api3Parser.sol";
import "../../PriceFeeds/Parsers/RedstoneParser.sol";
import "../../PriceFeeds/Parsers/TellorParser.sol";
import "../../PriceFeeds/Interfaces/IPriceFeed.sol";

contract ParserTester {
    using ChainlinkParser for address;
    using Api3Parser for address;
    using RedstoneParser for address;
    using TellorParser for address;

    address public chainlinkOracle;
    address public api3Oracle;
    address public redstoneOracle;
    address public tellorOracle;

    bytes32 tellorQueryId = keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd")));

    event ChainlinkResponse(uint256 price, uint256 lastUpdated);
    event Api3Response(uint256 price, uint256 lastUpdated);
    event RedstoneResponse(uint256 price, uint256 lastUpdated);
    event TellorResponse(uint256 price, uint256 lastUpdated);

    constructor(address _chainlinkOracle, address _api3Oracle, address _redstoneOracle, address _tellorOracle) {
        chainlinkOracle = _chainlinkOracle;
        api3Oracle = _api3Oracle;
        redstoneOracle = _redstoneOracle;
        tellorOracle = _tellorOracle;
    }

    function testChainlinkParser() public returns (uint256, uint256) {
        IPriceFeed.Response memory response = ChainlinkParser.getResponse(chainlinkOracle);
        emit ChainlinkResponse(response.price, response.lastUpdated);
        return (response.price, response.lastUpdated);
    }

    function testApi3Parser() public returns (uint256, uint256) {
        IPriceFeed.Response memory response = Api3Parser.getResponse(api3Oracle);
        emit Api3Response(response.price, response.lastUpdated);
        return (response.price, response.lastUpdated);
    }

    function testRedstoneParser() public returns (uint256, uint256) {
        IPriceFeed.Response memory response = RedstoneParser.getResponse(redstoneOracle);
        emit RedstoneResponse(response.price, response.lastUpdated);
        return (response.price, response.lastUpdated);
    }

    function testTellorParser() public returns (uint256, uint256) {
        IPriceFeed.Response memory response = TellorParser.getResponse(tellorOracle, tellorQueryId, 1000);
        emit TellorResponse(response.price, response.lastUpdated);
        return (response.price, response.lastUpdated);
    }
}