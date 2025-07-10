// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;
 
import "./CompositePriceFeed.sol";


contract WBTCPriceFeed is CompositePriceFeed {
    Oracle public btcUsdOracle;
    Oracle public wbtcUsdOracle;

    uint256 public constant WBTC_BTC_DEVIATION_THRESHOLD = 2e16; // 2%

    constructor(
        address _owner, 
        address _wbtcUsdOracleAddress, 
        address _btcUsdOracleAddress,
        uint256 _wbtcUsdStalenessThreshold,
        uint256 _btcUsdStalenessThreshold
    ) CompositePriceFeed(_owner, _wbtcUsdOracleAddress, _btcUsdOracleAddress, _wbtcUsdStalenessThreshold)
    {
        // Store BTC-USD oracle
        btcUsdOracle.aggregator = AggregatorV3Interface(_btcUsdOracleAddress);
        btcUsdOracle.stalenessThreshold = _btcUsdStalenessThreshold;
        btcUsdOracle.decimals = btcUsdOracle.aggregator.decimals();

        // Store wBTC-USD oracle
        wbtcUsdOracle.aggregator = AggregatorV3Interface(_wbtcUsdOracleAddress);
        wbtcUsdOracle.stalenessThreshold = _wbtcUsdStalenessThreshold;
        wbtcUsdOracle.decimals = wbtcUsdOracle.aggregator.decimals();

        _fetchPricePrimary(false);

        // Check the oracle didn't already fail
        assert(priceSource == PriceSource.primary);
    }

    function _fetchPricePrimary(bool _isRedemption) internal override returns (uint256, bool) {
        assert(priceSource == PriceSource.primary);
        (uint256 wbtcUsdPrice, bool wbtcUsdOracleDown) = _getOracleAnswer(wbtcUsdOracle);
        (uint256 btcUsdPrice, bool btcOracleDown) = _getOracleAnswer(btcUsdOracle);
        
        // tBTC oracle is down or invalid answer
        if (wbtcUsdOracleDown) {
            return (_shutDownAndSwitchToLastGoodPrice(address(wbtcUsdOracle.aggregator)), true);
        }

        // BTC oracle is down or invalid answer
        if (btcOracleDown) {
            return (_shutDownAndSwitchToLastGoodPrice(address(btcUsdOracle.aggregator)), true);
        }

        // Otherwise, use the primary price calculation:
        if (_isRedemption && _withinDeviationThreshold(wbtcUsdPrice, btcUsdPrice, WBTC_BTC_DEVIATION_THRESHOLD)) {
            // If it's a redemption and within 2%, take the max of (wBTC-USD, BTC-USD) to prevent value leakage and convert to wBTC-USD
            wbtcUsdPrice = LiquityMath._max(wbtcUsdPrice, btcUsdPrice);
        }else{
            // Take the minimum of (market, canonical) in order to mitigate against upward market price manipulation.
            wbtcUsdPrice = LiquityMath._min(wbtcUsdPrice, btcUsdPrice);
        }

        // Otherwise, just use wBTC-USD price: USD_per_wBTC.
        lastGoodPrice = wbtcUsdPrice;
        return (wbtcUsdPrice, false);
    }

    function _getCanonicalRate() internal view override returns (uint256, bool) {
        return (1 * 10 ** 18, false); // always return 1 BTC per wBTC by default.
    }
}   


