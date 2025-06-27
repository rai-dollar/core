// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IPriceFeed {
    enum PriceSource {
        primaryOracle, 
        fallbackOracle,
        lastGoodPrice
    }

    struct Response {
        uint256 price;
        uint256 lastUpdated;
        bool success;
    }

    struct Oracle {
        address oracle;
        uint256 stalenessThreshold;
    }

    struct OracleConfig {
        address primaryOracle;
        address fallbackOracle;
        uint256 primaryStalenessThreshold;
        uint256 fallbackStalenessThreshold;
    }

    // --- Function ---
    function fetchPrice(bool _isRedemption) external returns (uint256);
}
