// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Dependencies/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}
