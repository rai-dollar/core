pragma solidity 0.8.24;

interface IRateControl {
    function RAY() external view returns (uint256);
    function authorities(address) external view returns (uint256);
    function boundPiOutput(int256 piOutput) external view returns (int256);
    function coBias() external view returns (int256);
    function controlVariable() external view returns (bytes32);
    function elapsed() external view returns (uint256);
    function errorIntegral() external view returns (int256);
    function getNextErrorIntegral(int256 error) external view returns (int256, int256);
    function getNextPiOutput(int256 error) external view returns (int256, int256, int256);
    function getRawPiOutput(int256 error, int256 errorI) external view returns (int256, int256, int256);
    function ki() external view returns (int256);
    function kp() external view returns (int256);
    function lastError() external view returns (int256);
    function lastUpdateTime() external view returns (uint256);
    function outputLowerBound() external view returns (int256);
    function outputUpperBound() external view returns (int256);
    function perSecondIntegralLeak() external view returns (uint256);
    function riemannSum(int256 x, int256 y) external pure returns (int256 z);
    function rpower(uint256 x, uint256 n, uint256 base) external pure returns (uint256 z);
    function update(int256 error) external returns (int256, int256, int256);
    function updater() external view returns (address);
}
