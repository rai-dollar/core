// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IApi3ReaderProxy {
    function read() external view returns (int224 value, uint32 timestamp);
    function decimals() external view returns (uint8);
}
