// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract MarketOracleTestnet {

    int256 public price;

    function setPrice(int256 newPrice) external returns (int256) {
        price = newPrice;
    }
}
