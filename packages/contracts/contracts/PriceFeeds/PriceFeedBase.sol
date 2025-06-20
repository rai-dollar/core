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
    function fetchPrice() external virtual returns (uint) {
        if (status == Status.shutdown) {
            revert Shutdown();
        }

        Response memory primaryResponse = _fetchPriceFromPrimaryOracle();
        bool isGoodPrimaryResponse = _isGoodPrimaryResponse(primaryResponse);
        

        if (isGoodPrimaryResponse) {
            _changeStatus(Status.primaryOracle);
            _storeResponse(primaryResponse);
            
            return primaryResponse.price;
        } 

        Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
        bool isGoodFallbackResponse = _isGoodFallbackResponse(fallbackResponse);

        if (isGoodFallbackResponse) {
            _changeStatus(Status.fallbackOracle);
            _storeResponse(fallbackResponse);
            
            return fallbackResponse.price;
        } 

        _changeStatus(Status.shutdown);
        revert NoGoodResponseFromAnyOracle();
    }
    
    function _withinDeviationThreshold(Response memory _currentResponse, Response memory _lastGoodResponse, uint256 _deviationThreshold)
        internal
        pure
        returns (bool)
    {
        // Calculate the price deviation of the oracle market price relative to the canonical price
        uint256 max = _currentResponse.price * (C.DECIMAL_PRECISION + _deviationThreshold) / 1e18;
        uint256 min = _lastGoodResponse.price * (C.DECIMAL_PRECISION - _deviationThreshold) / 1e18;

        return _currentResponse.price >= min && _currentResponse.price <= max;
    }

    // --- Overrides ---

    function _getEthUsdPrice() internal virtual returns (uint256 price, bool success);

    // must override with correct logic for each collateral type
    function _getRate() internal virtual returns (uint256 rate, bool success);

    function _isWithinDeviationThreshold(Response memory _currentResponse) internal virtual returns (bool);
 
    function _fetchPriceFromPrimaryOracle() internal virtual returns (Response memory);

    function _fetchPriceFromFallbackOracle() internal virtual returns (Response memory);

    function _isGoodPrimaryResponse(Response memory _response) internal virtual returns (bool);

    function _isGoodFallbackResponse(Response memory _response) internal virtual returns (bool);

    // --- Helper functions ---

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

