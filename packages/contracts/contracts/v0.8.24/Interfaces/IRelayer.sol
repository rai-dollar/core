// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IRelayer {
    // Events
    event ParControlAddressChanged(address newAddress);
    event RateControlAddressChanged(address newAddress);
    event MarketOracleAddressChanged(address newAddress);
    event TroveManagerAddressChanged(address newAddress);
    event ParUpdated(int256 par, int256 pOutput, int256 iOutput, int256 error);
    event RateUpdated(int256 rate, int256 pOutput, int256 iOutput, int256 error);

    // External functions
    function setAddresses(
        address parControlAddress,
        address rateControlAddress,
        address marketOracleAddress,
        address troveManagerAddress
    ) external;

    function controlError(uint256 market) external pure returns (int256);
    function parControlError(uint256 market) external pure returns (int256);
    function rateControlError(uint256 market, uint256 par) external pure returns (int256);

    function updatePar() external returns (uint256);
    function updateRate() external returns (uint256);

    // Getters for external contracts
    function parControl() external view returns (address);
    function rateControl() external view returns (address);
    function marketOracle() external view returns (address);
    function troveManager() external view returns (address);
}
