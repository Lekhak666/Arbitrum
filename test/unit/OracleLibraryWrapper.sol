// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OracleLibrary} from "../../src/libraries/OracleLibrary.sol";

/// @dev Foundry can't call `internal` library functions directly from tests.
///      This thin wrapper exposes them as `external` so the test suite can
///      call them like any normal contract method.
contract OracleLibraryWrapper {
    function consult(address pool, uint32 secondsAgo)
        external
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        return OracleLibrary.consult(pool, secondsAgo);
    }

    function getQuoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        external
        pure
        returns (uint256 quoteAmount)
    {
        return OracleLibrary.getQuoteAtTick(tick, baseAmount, baseToken, quoteToken);
    }

    function getOldestObservationSecondsAgo(address pool) external view returns (uint32 secondsAgo) {
        return OracleLibrary.getOldestObservationSecondsAgo(pool);
    }

    function getBlockStartingTickAndLiquidity(address pool) external view returns (int24 tick, uint128 liq) {
        return OracleLibrary.getBlockStartingTickAndLiquidity(pool);
    }

    function getWeightedArithmeticMeanTick(OracleLibrary.WeightedTickData[] memory weightedTickData)
        external
        pure
        returns (int24 weightedArithmeticMeanTick)
    {
        return OracleLibrary.getWeightedArithmeticMeanTick(weightedTickData);
    }

    function getChainedPrice(address[] memory tokens, int24[] memory ticks)
        external
        pure
        returns (int256 syntheticTick)
    {
        return OracleLibrary.getChainedPrice(tokens, ticks);
    }
}
