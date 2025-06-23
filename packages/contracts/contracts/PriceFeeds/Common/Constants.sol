// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


library Constants {
uint256 public constant PRICE_DECIMALS = 18;
uint256 public constant TWAP_AGE = 60;

uint256 public constant CHAINLINK_STALENESS_THRESHOLD = 24 hours;
uint256 public constant API3_STALENESS_THRESHOLD = 24 hours;
uint256 public constant TELLOR_STALENESS_THRESHOLD = 24 hours;
uint256 public constant REDSTONE_STALENESS_THRESHOLD = 24 hours;

uint256 public constant DECIMAL_PRECISION = 1e18;

// deviation thresholds
uint256 public constant STETH_USD_DEVIATION_THRESHOLD = 1e16; // 1%
uint256 public constant RETH_ETH_DEVIATION_THRESHOLD = 2e16; // 2%
uint256 public constant WBTC_BTC_DEVIATION_THRESHOLD = 2e16; // 2%
uint256 public constant ETH_USD_DEVIATION_THRESHOLD = 1e16; // 1%
}