// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {IERC20} from "./Interfaces/IERC20.sol";
import {Constants as C} from "./Common/Constants.sol";

/*
* PriceFeed for mainnet deployment, to be connected to Chainlink's live ETH:USD aggregator reference 
* contract, and a wrapper contract TellorCaller, which connects to TellorMaster contract.
*
* The PriceFeed uses Chainlink as primary oracle, and Tellor as fallback. It contains logic for
* switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
* Chainlink oracle.
*/
abstract contract PriceFeedBase is IPriceFeed {
    using LiquityMath for uint256;
    
    // this should be the token / usd oracle
    address public primaryOracle;
    // this is the fallback in case the primary oracle fails
    address public fallbackOracle;
    
    // this is the base token for which the price is being fetched
    IERC20 public token;

    // The last good price seen from an oracle by Liquity
    Response public lastGoodResponse;
    
    // The current status of the PricFeed, which determines the conditions for the next price fetch attempt
    Status public status;

    constructor(address _primaryOracle, address _fallbackOracle, address _token) {
        primaryOracle = _primaryOracle;
        fallbackOracle = _fallbackOracle;
        token = IERC20(_token);
        assert(token.decimals() != 0);
        status = Status.primaryOracle;
    }

    // --- Functions ---

    // must override with specific logic for each collateral type and oracle combination
    function fetchPrice() external virtual returns (uint256);

    function _fetchTokenOraclePrice() internal returns (uint256 price){
        Response memory primaryResponse = _fetchPriceFromPrimaryOracle();
        bool isGoodPrimaryResponse = isGoodResponse(primaryResponse, _primaryStalenessThreshold());
        
        if (isGoodPrimaryResponse) {
            _withinDeviationThreshold(primaryResponse);
            _changeStatus(Status.primaryOracle);
            _storeResponse(primaryResponse);
            
            return primaryResponse.price;
        } 

        Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
        bool isGoodFallbackResponse = isGoodResponse(fallbackResponse, _fallbackStalenessThreshold());

        if (isGoodFallbackResponse) {
            _withinDeviationThreshold(fallbackResponse);
            _changeStatus(Status.fallbackOracle);
            _storeResponse(fallbackResponse);
            
            return fallbackResponse.price;
        }

        // if primary and fallback are both bad, shutdown the price feed and revert to last good price
        if (!isGoodPrimaryResponse && !isGoodFallbackResponse) {
            _changeStatus(Status.shutdown);
            return lastGoodResponse.price;
        }

    }
    
    // deviation threshold is per collateral type
    function _withinDeviationThreshold(Response memory _currentResponse)
        internal
        pure
        returns (bool)
    {
        // Calculate the price deviation of the oracle market price relative to the canonical price
        uint256 max = _currentResponse.price * (C.DECIMAL_PRECISION + _deviationThreshold()) / C.DECIMAL_PRECISION;
        uint256 min = lastGoodResponse.price * (C.DECIMAL_PRECISION - _deviationThreshold()) / C.DECIMAL_PRECISION;

        return _currentResponse.price >= min && _currentResponse.price <= max;
    }

    // --- Overrides ---
    /// @notice must override all functions below with the library for the selected oracle
    
    // must override with the library of the primary oracle
    function _fetchPriceFromPrimaryOracle() internal virtual returns (Response memory);

    // must override with the library of the fallback oracle
    function _fetchPriceFromFallbackOracle() internal virtual returns (Response memory);

    // must override with the deviation threshold from the library of the primary oracle
    function _primaryStalenessThreshold() internal pure virtual returns (uint256);

    // must override with the deviation threshold from the library of the fallback oracle
    function _fallbackStalenessThreshold() internal pure virtual returns (uint256);

    // must override with the deviation threshold for the collateral type Found in Constants.sol
    function _deviationThreshold() internal pure virtual returns (uint256);
    

    // --- Helper functions ---

    function isGoodResponse(IPriceFeed.Response memory _response, uint256 _staleThreshold) public view returns (bool) {
        return _response.success && _response.price > 0 && _response.lastUpdated > 0 && block.timestamp - _response.lastUpdated > _staleThreshold;
    }

    function _changeStatus(Status _status) internal {
        if (status != _status) {
            status = _status;
            emit PriceFeedStatusChanged(_status);
        }
    }

    function _storeResponse(Response memory _response) internal {
        lastGoodResponse = _response;
        emit LastGoodResponseUpdated(_response.price, _response.lastUpdated);
    }


}

