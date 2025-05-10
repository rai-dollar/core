// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./v0.8.24/Interfaces/IParControl.sol";
import "./v0.8.24/Interfaces/IRateControl.sol";
import "./v0.8.24/Interfaces/IMarketOracle.sol";
import "./v0.8.24/Interfaces/ITroveManager.sol";
import "./v0.8.24/Dependencies/Ownable.sol";
import "./v0.8.24/Dependencies/CheckContract.sol";

contract Relayer is Ownable, CheckContract {
    int256 constant public DECIMAL_PRECISION_I = 1e18;
    event ParControlAddressChanged(address newAddress);
    event RateControlAddressChanged(address newAddress);
    event MarketOracleAddressChanged(address newAddress);
    event TroveManagerAddressChanged(address newAddress);
    event ParUpdated(int256 par, int256 pOutput, int256 iOutput, int256 error);
    event RateUpdated(int256 rate, int256 pOutput, int256 iOutput, int256 error);

    IParControl public parControl;
    IRateControl public rateControl;
    IMarketOracle public marketOracle;
    ITroveManager public troveManager;

    function setAddresses(
        address parControlAddress,
        address rateControlAddress,
        address marketOracleAddress,
        address troveManagerAddress
    ) external onlyOwner {
        checkContract(parControlAddress);
        checkContract(rateControlAddress);
        checkContract(marketOracleAddress);
        checkContract(troveManagerAddress);

        parControl = IParControl(parControlAddress);
        rateControl = IRateControl(rateControlAddress);
        marketOracle = IMarketOracle(marketOracleAddress);
        troveManager = ITroveManager(troveManagerAddress);

        emit ParControlAddressChanged(parControlAddress);
        emit RateControlAddressChanged(rateControlAddress);
        emit MarketOracleAddressChanged(marketOracleAddress);
        emit TroveManagerAddressChanged(troveManagerAddress);

        _renounceOwnership();
    }

    function controlError(uint256 market) external pure returns (int256) {
        return _controlError(market);
    }

    function _controlError(uint256 market) internal pure returns (int256) {
        return DECIMAL_PRECISION_I - int256(market);
    }

    function parControlError(uint256 market) external pure returns (int256) {
        return _parControlError(market);
    }

    function _parControlError(uint256 market) internal pure returns (int256) {
        return DECIMAL_PRECISION_I - int256(market);
    }

    function rateControlError(uint256 market, uint256 par) external pure returns (int256) {
        return _rateControlError(market, par);
    }

    function _rateControlError(uint256 market, uint256 par) internal pure returns (int256) {
        int256 parI = int256(par);
        return ((parI - int256(market)) * DECIMAL_PRECISION_I) / parI;
    }

    function updatePar() external returns (uint256) {
        return _updatePar();
    }

    function _updatePar() internal returns (uint256) {
        uint256 market = marketOracle.price();
        int256 error = _parControlError(market);

        (int256 par, int256 pOutput, int256 iOutput) = rateControl.update(error);

        emit ParUpdated(par, pOutput, iOutput, error);

        return uint256(par);
    }

    function updateRate() external returns (uint256) {
        // TODO: set rate on TroveManager
        uint256 market = marketOracle.price();
        uint256 par = _updatePar();
        int256 error = _rateControlError(market, par);

        (int256 rate, int256 pOutput, int256 iOutput) = rateControl.update(error);
        emit RateUpdated(rate, pOutput, iOutput, error);

        return uint256(rate);
    }
}
