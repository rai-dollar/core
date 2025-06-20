// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


library Constants {
uint256 public constant PRICE_DECIMALS = 18;
uint256 public constant TWAP_AGE = 60;

uint256 public constant CHAINLINK_STALENESS_THRESHOLD = 24 hours;
uint256 public constant API3_STALENESS_THRESHOLD = 24 hours;
uint256 public constant TELLOR_STALENESS_THRESHOLD = 24 hours;

uint256 public constant CHAINLINK_MAX_PRICE_DEVIATION = 5e17; // 50%
uint256 public constant API3_MAX_PRICE_DEVIATION = 5e17; // 50%
uint256 public constant TELLOR_MAX_PRICE_DEVIATION = 5e17; // 50%


uint256 public constant DECIMAL_PRECISION = 1e18;
}