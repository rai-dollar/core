// SPDX-License-Identifier: MIT
import "./IPriceFeed.sol";
import "../../v0.8.24/Dependencies/AggregatorV3Interface.sol";

pragma solidity ^0.8.0;

interface IMainnetPriceFeed is IPriceFeed {
    enum PriceSource {
        primary,
        ETHUSDxCanonical,
        lastGoodPrice
    }

    function ethUsdOracle() external view returns (AggregatorV3Interface, uint256, uint8);
    function priceSource() external view returns (PriceSource);
}
