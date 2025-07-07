// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../RDOracle.sol";

contract RDOracleTestHelper is RDOracle {
    constructor(
        address _vault,
        address _rdToken,
        uint32 _quotePeriodFast,
        uint32 _quotePeriodSlow,
        address[] memory _stablecoins,
        uint32 _minObservationDelta
    )
        RDOracle(
            _vault,
            _rdToken,
            _quotePeriodFast,
            _quotePeriodSlow,
            _stablecoins,
            _minObservationDelta
        )
    {}

    // Expose the internal _calculateMedian function for testing
    function testCalculateMedian(uint256[] memory _arr) external pure returns (uint256) {
        return _calculateMedian(_arr);
    }

    // Expose other internal functions if needed
    function testConvertPriceToSqrtPriceX96(uint256 _price) external pure returns (uint160) {
        return _convertPriceToSqrtPriceX96(_price);
    }

    function testConvertSqrtPriceX96ToPrice(uint160 _sqrtPriceX96) external pure returns (uint256) {
        return _convertSqrtPriceX96ToPrice(_sqrtPriceX96);
    }

    function testCalculatePartialDerivative(
        uint256 _tokenBalance,
        uint256 _ampCoefficient,
        uint256 _poolInvariant,
        uint256 _balancesSum,
        uint256 _ampPrecision
    ) external pure returns (uint256) {
        return
            _calculatePartialDerivative(
                _tokenBalance,
                _ampCoefficient,
                _poolInvariant,
                _balancesSum,
                _ampPrecision
            );
    }
}
