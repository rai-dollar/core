// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./MockERC20.sol";

contract MockWstETH is MockERC20 {
    
 constructor () MockERC20("Wrapped Staked ETH", "wstETH", 18) {}

     /**
     * @notice Get amount of stETH for a one wstETH
     * @return Amount of stETH for 1 wstETH
     */
    function stEthPerToken() external view returns (uint256) {
        return 1.1e18;
    }

    /**
     * @notice Get amount of wstETH for a one stETH
     * @return Amount of wstETH for a 1 stETH
     */
    function tokensPerStEth() external view returns (uint256) {
        return 0.9e18;
    }

     /**
     * @notice Get amount of wstETH for a given amount of stETH
     * @param _stETHAmount amount of stETH
     * @return Amount of wstETH for a given stETH amount
     */
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256) {
        return _stETHAmount * 1.1e18;
    }

    /**
     * @notice Get amount of stETH for a given amount of wstETH
     * @param _wstETHAmount amount of wstETH
     * @return Amount of stETH for a given wstETH amount
     */
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256) {
        return _wstETHAmount / 1.1e18;
    }

}
