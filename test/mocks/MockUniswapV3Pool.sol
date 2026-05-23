// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal mock of IUniswapV3Pool for OracleLibrary tests.
///      Only the functions called by OracleLibrary are implemented.
contract MockUniswapV3Pool {
    // --- slot0 data ---
    int24 public slot0Tick;
    uint16 public observationIndex;
    uint16 public observationCardinality;

    // --- liquidity ---
    uint128 public liquidityValue;

    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }

    Observation[] public observations;

    // --- observe() return data (set per-test) ---
    int56[] internal _tickCumulatives;
    uint160[] internal _secondsPerLiquidityCumulativeX128s;

    /*//////////////////////////////////////////////////////////////
                            SETUP HELPERS
    //////////////////////////////////////////////////////////////*/

    function setSlot0(int24 tick, uint16 obsIndex, uint16 obsCardinality) external {
        slot0Tick = tick;
        observationIndex = obsIndex;
        observationCardinality = obsCardinality;
    }

    function setLiquidity(uint128 liq) external {
        liquidityValue = liq;
    }

    /// @dev Push observations in order (index 0 first).
    function pushObservation(
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    ) external {
        observations.push(
            Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: tickCumulative,
                secondsPerLiquidityCumulativeX128: secondsPerLiquidityCumulativeX128,
                initialized: initialized
            })
        );
    }

    /// @dev Override the full observations array from scratch.
    function clearObservations() external {
        delete observations;
    }

    /// @dev Set what `observe()` will return (called by consult()).
    function setObserveData(int56[] calldata tickCumulatives, uint160[] calldata spLiqCumulatives) external {
        delete _tickCumulatives;
        delete _secondsPerLiquidityCumulativeX128s;
        for (uint256 i; i < tickCumulatives.length; i++) {
            _tickCumulatives.push(tickCumulatives[i]);
            _secondsPerLiquidityCumulativeX128s.push(spLiqCumulatives[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      IUniswapV3Pool INTERFACE STUBS
    //////////////////////////////////////////////////////////////*/

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 _observationIndex,
            uint16 _observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (0, slot0Tick, observationIndex, observationCardinality, observationCardinality, 0, true);
    }

    function liquidity() external view returns (uint128) {
        return liquidityValue;
    }

    function observe(
        uint32[] calldata /*secondsAgos*/
    )
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return (_tickCumulatives, _secondsPerLiquidityCumulativeX128s);
    }

    function observation(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        Observation memory o = observations[index];
        return (o.blockTimestamp, o.tickCumulative, o.secondsPerLiquidityCumulativeX128, o.initialized);
    }

    // --- unused stubs required by the interface ---
    function token0() external pure returns (address) {
        return address(0);
    }

    function token1() external pure returns (address) {
        return address(0);
    }

    function fee() external pure returns (uint24) {
        return 0;
    }

    function tickSpacing() external pure returns (int24) {
        return 0;
    }

    function maxLiquidityPerTick() external pure returns (uint128) {
        return 0;
    }
}
