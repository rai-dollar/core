// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IPriceFeed {
    enum Status {
        primaryOracle, 
        fallbackOracle,
        shutdown
    }

    struct Response {
        uint256 price;
        uint256 lastUpdated;
        bool success;
    }

    // --- Events ---
    event LastGoodResponseUpdated(uint _lastGoodPrice, uint256 timestamp);
    event PriceFeedStatusChanged(Status newStatus);
    error NoGoodResponseFromAnyOracle();
    error InsufficientGasForExternalCall();
    error Shutdown();
   
    // --- Function ---
    function fetchPrice() external returns (uint);
}
