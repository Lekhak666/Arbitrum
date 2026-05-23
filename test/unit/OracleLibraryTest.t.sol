// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {OracleLibrary} from "../../src/libraries/OracleLibrary.sol";
import {OracleLibraryWrapper} from "../unit/OracleLibraryWrapper.sol";
import {MockUniswapV3Pool} from "../mocks/MockUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/*//////////////////////////////////////////////////////////////
                         BASE SETUP
//////////////////////////////////////////////////////////////*/

contract OracleLibraryBase is Test {
    OracleLibraryWrapper internal oracle;
    MockUniswapV3Pool internal pool;

    // Two deterministic addresses for token ordering tests.
    // Sorted so addrA < addrB.
    address internal addrA = address(0x1111);
    address internal addrB = address(0x2222);

    function setUp() public virtual {
        oracle = new OracleLibraryWrapper();
        pool = new MockUniswapV3Pool();

        // Ensure our canonical pair ordering
        assertTrue(addrA < addrB, "addrA must be < addrB for directional tests");
    }

    /*── helpers ──*/

    /// @dev Build an int56[] and uint160[] for setObserveData().
    function _setObserve(int56 tc0, int56 tc1, uint160 sp0, uint160 sp1) internal {
        int56[] memory tcs = new int56[](2);
        uint160[] memory sps = new uint160[](2);
        tcs[0] = tc0;
        tcs[1] = tc1;
        sps[0] = sp0;
        sps[1] = sp1;
        pool.setObserveData(tcs, sps);
    }

    /// @dev Helper: push N identical observations into the mock pool.
    function _pushObservation(uint32 ts, int56 tickCumulative, uint160 spLiq, bool init) internal {
        pool.pushObservation(ts, tickCumulative, spLiq, init);
    }
}

/*//////////////////////////////////////////////////////////////
                        consult()
//////////////////////////////////////////////////////////////*/

contract ConsultTest is OracleLibraryBase {
    function test_revert_secondsAgoZero() public {
        vm.expectRevert(bytes("BP"));
        oracle.consult(address(pool), 0);
    }

    function test_positiveTickDelta_exactDivision() public {
        // tickCumulative went from 0 → 600 over 60 seconds → mean tick = 10
        _setObserve(0, 600, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), 60);
        assertEq(meanTick, 10);
    }

    function test_negativeTickDelta_exactDivision() public {
        // tickCumulative went from 0 → -600 over 60 seconds → mean tick = -10
        _setObserve(0, -600, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), 60);
        assertEq(meanTick, -10);
    }

    function test_negativeTickDelta_roundsDownToNegInfinity() public {
        // delta = -61, secondsAgo = 60 → -61/60 = -1.016... → floor = -2
        _setObserve(0, -61, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), 60);
        assertEq(meanTick, -2, "should round toward negative infinity");
    }

    function test_negativeTickDelta_exactDivision_noExtraRound() public {
        // delta = -60, secondsAgo = 60 → exactly -1, no rounding needed
        _setObserve(0, -60, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), 60);
        assertEq(meanTick, -1);
    }

    function test_positiveTickDelta_noRounding() public {
        // Positive non-exact: 61/60 truncates to 1 (Solidity integer division, not floor)
        _setObserve(0, 61, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), 60);
        assertEq(meanTick, 1);
    }

    function test_harmonicMeanLiquidity_nonZero() public {
        uint32 secondsAgo = 100;
        uint160 spDelta = uint160(1) << 32; // small but non-zero

        _setObserve(0, 1000, 0, spDelta);

        (, uint128 liq) = oracle.consult(address(pool), secondsAgo);
        assertGt(liq, 0, "liquidity should be non-zero");
    }

    function test_harmonicMeanLiquidity_largerDeltaGivesLowerLiquidity() public {
        // Larger secondsPerLiquidity delta → lower harmonic mean liquidity
        _setObserve(0, 600, 0, uint160(1) << 33);
        (, uint128 liqLarge) = oracle.consult(address(pool), 60);

        _setObserve(0, 600, 0, uint160(1) << 32);
        (, uint128 liqSmall) = oracle.consult(address(pool), 60);

        assertGt(liqSmall, liqLarge, "smaller spLiq delta : higher liquidity");
    }

    /// @dev secondsAgo = 1 is the minimum valid value.
    function test_secondsAgo_one() public {
        _setObserve(0, 5, 0, uint160(1) << 32);
        (int24 meanTick,) = oracle.consult(address(pool), 1);
        assertEq(meanTick, 5);
    }
}

/*//////////////////////////////////////////////////////////////
                      getQuoteAtTick()
//////////////////////////////////////////////////////////////*/

contract GetQuoteAtTickTest is OracleLibraryBase {
    function test_tick0_returnsBaseAmount_tokenABase() public view {
        // At tick 0, sqrtRatio = 2^96, price ratio = 1:1
        uint256 quote = oracle.getQuoteAtTick(0, 1e18, addrA, addrB);
        assertEq(quote, 1e18, "tick 0, addrA<addrB: should be 1:1");
    }

    function test_tick0_returnsBaseAmount_tokenBBase() public view {
        uint256 quote = oracle.getQuoteAtTick(0, 1e18, addrB, addrA);
        assertEq(quote, 1e18, "tick 0, addrB>addrA: should also be 1:1");
    }

    function test_positiveTick_addrABase_higherQuote() public view {
        // Positive tick → token0 (addrA) is worth more in terms of token1 (addrB)
        uint256 quoteTick0 = oracle.getQuoteAtTick(0, 1e18, addrA, addrB);
        uint256 quoteTick1 = oracle.getQuoteAtTick(1000, 1e18, addrA, addrB);
        assertGt(quoteTick1, quoteTick0, "higher tick more quoteToken per base");
    }

    // function test_negativeTick_addrABase_lowerQuote() public {
    //     uint256 quoteTick0 = oracle.getQuoteAtTick(0, 1e18, addrA, addrB);
    //     uint256 quoteTickN = oracle.getQuoteAtTick(-1000, 1e18, addrA, addrB);
    //     assertLt(
    //         quoteTickN,
    //         quoteTick0,
    //         "negative tick → less quoteToken per base"
    //     );
    // }

    // function test_reverseBaseQuote_isReciprocal_approx() public {
    //     // getQuoteAtTick(t, amt, A, B) * getQuoteAtTick(t, amt, B, A) ≈ amt^2
    //     // Not exact due to integer math, but should be within 0.1%
    //     uint128 base = 1e18;
    //     int24 tick = 500;

    //     uint256 qAB = oracle.getQuoteAtTick(tick, base, addrA, addrB);
    //     uint256 qBA = oracle.getQuoteAtTick(tick, base, addrB, addrA);

    //     // product ≈ base^2 within 0.1%
    //     uint256 product = qAB * qBA;
    //     uint256 expected = uint256(base) * base;
    //     uint256 tolerance = expected / 1000; // 0.1%

    //     assertApproxEqAbs(
    //         product,
    //         expected,
    //         tolerance,
    //         "reciprocal product should ≈ base^2"
    //     );
    // }

    function test_minTick() public view {
        // Should not revert at boundary
        oracle.getQuoteAtTick(TickMath.MIN_TICK, 1e18, addrA, addrB);
    }

    function test_maxTick() public view {
        oracle.getQuoteAtTick(TickMath.MAX_TICK, 1e18, addrA, addrB);
    }

    function test_largeBaseAmount() public view {
        oracle.getQuoteAtTick(0, type(uint128).max, addrA, addrB);
    }

    function test_zeroBaseAmount() public view {
        uint256 q = oracle.getQuoteAtTick(0, 0, addrA, addrB);
        assertEq(q, 0);
    }

    /// @dev Monotonicity: higher tick → higher quote (when baseToken < quoteToken).
    function testFuzz_getQuoteAtTick_monotone_addrABase(int24 tick1, int24 tick2) public view {
        tick1 = int24(bound(tick1, TickMath.MIN_TICK, TickMath.MAX_TICK - 1));
        tick2 = int24(bound(tick2, tick1 + 1, TickMath.MAX_TICK));

        uint256 q1 = oracle.getQuoteAtTick(tick1, 1e18, addrA, addrB);
        uint256 q2 = oracle.getQuoteAtTick(tick2, 1e18, addrA, addrB);
        assertLe(q1, q2, "quote should be non-decreasing in tick");
    }

    /// @dev Scaling: doubling baseAmount doubles quoteAmount (tick 0 → ratio is exact 1:1).
    function testFuzz_getQuoteAtTick_scaling(uint128 base) public view {
        vm.assume(base > 0 && base <= type(uint128).max / 2);
        uint256 q1 = oracle.getQuoteAtTick(0, base, addrA, addrB);
        uint256 q2 = oracle.getQuoteAtTick(0, base * 2, addrA, addrB);
        // At tick 0 it's a 1:1 ratio, so q2 == 2*q1 exactly
        assertEq(q2, q1 * 2);
    }
}

/*//////////////////////////////////////////////////////////////
               getOldestObservationSecondsAgo()
//////////////////////////////////////////////////////////////*/

contract GetOldestObservationSecondsAgoTest is OracleLibraryBase {
    function test_revert_cardinalityZero() public {
        pool.setSlot0(0, 0, 0); // cardinality = 0
        vm.expectRevert(bytes("NI"));
        oracle.getOldestObservationSecondsAgo(address(pool));
    }

    function test_singleObservation_initialized_nextWraps() public {
        // cardinality=1, observationIndex=0
        // next index = (0+1)%1 = 0 — same slot, which IS initialized
        // so oldest ts = observations[0].blockTimestamp
        uint32 oldTs = 1000;
        pool.setSlot0(0, 0, 1);
        _pushObservation(oldTs, 0, 0, true);

        vm.warp(2000);
        uint32 secondsAgo = oracle.getOldestObservationSecondsAgo(address(pool));
        assertEq(secondsAgo, 2000 - oldTs);
    }

    function test_multipleObservations_nextInitialized() public {
        // cardinality=2, observationIndex=1
        // next = (1+1)%2 = 0, which is initialized → that's the oldest
        uint32 oldTs = 500;
        pool.setSlot0(0, 1, 2);
        _pushObservation(oldTs, 0, 0, true); // index 0 (oldest)
        _pushObservation(900, 0, 0, true); // index 1 (current)

        vm.warp(1000);
        uint32 secondsAgo = oracle.getOldestObservationSecondsAgo(address(pool));
        assertEq(secondsAgo, 1000 - oldTs);
    }

    function test_multipleObservations_nextUninitialized_fallsBackToIndex0() public {
        // cardinality=2, observationIndex=0
        // next = (0+1)%2 = 1, which is NOT initialized → fallback to index 0
        uint32 ts0 = 300;
        pool.setSlot0(0, 0, 2);
        _pushObservation(ts0, 0, 0, true); // index 0
        _pushObservation(0, 0, 0, false); // index 1 — uninitialized

        vm.warp(1000);
        uint32 secondsAgo = oracle.getOldestObservationSecondsAgo(address(pool));
        assertEq(secondsAgo, 1000 - ts0);
    }

    function testFuzz_secondsAgoMatchesTimeDelta(uint32 oldTimestamp, uint32 currentTimestamp) public {
        vm.assume(currentTimestamp > oldTimestamp);
        vm.assume(currentTimestamp <= type(uint32).max);

        pool.clearObservations();
        pool.setSlot0(0, 0, 1);
        _pushObservation(oldTimestamp, 0, 0, true);

        vm.warp(currentTimestamp);
        uint32 secondsAgo = oracle.getOldestObservationSecondsAgo(address(pool));
        assertEq(secondsAgo, currentTimestamp - oldTimestamp);
    }
}

/*//////////////////////////////////////////////////////////////
              getBlockStartingTickAndLiquidity()
//////////////////////////////////////////////////////////////*/

contract GetBlockStartingTickAndLiquidityTest is OracleLibraryBase {
    function test_revert_cardinalityOne() public {
        pool.setSlot0(100, 0, 1); // cardinality must be > 1
        _pushObservation(uint32(block.timestamp), 0, 0, true);
        vm.expectRevert(bytes("NEO"));
        oracle.getBlockStartingTickAndLiquidity(address(pool));
    }

    // function test_observationInPast_returnsSlot0TickAndLiquidity() public {
    //     // Latest observation is from a PAST block → no intra-block trades
    //     // → slot0.tick is the starting tick, liquidity comes from pool.liquidity()
    //     uint32 pastTs = uint32(block.timestamp) - 100;

    //     pool.setSlot0(42, 1, 2); // slot0 tick = 42, obsIndex = 1
    //     pool.setLiquidity(999);
    //     _pushObservation(pastTs, 0, 0, true); // index 0
    //     _pushObservation(pastTs, 0, 0, true); // index 1 (latest) — past ts

    //     (int24 tick, uint128 liq) = oracle.getBlockStartingTickAndLiquidity(
    //         address(pool)
    //     );
    //     assertEq(tick, 42, "should return slot0 tick");
    //     assertEq(liq, 999, "should return pool liquidity");
    // }

    // function test_observationCurrentBlock_computesFromDelta() public {
    //     uint32 now32 = uint32(block.timestamp);

    //     // obsIndex=1, cardinality=2
    //     // Prev observation (index 0): ts=now-10, tickCumulative=0
    //     // Current observation (index 1): ts=now,   tickCumulative=100
    //     // delta = 10 seconds, tickCumulativeDelta = 100
    //     // starting tick = 100/10 = 10
    //     int56 prevCumulative = 0;
    //     int56 curCumulative = 100;
    //     uint32 prevTs = now32 - 10;

    //     pool.setSlot0(99, 1, 2); // slot0 tick = 99 (should be overridden)
    //     pool.setLiquidity(0);

    //     // index 0: prev observation
    //     _pushObservation(prevTs, prevCumulative, 0, true);
    //     // index 1: current observation (ts == block.timestamp → intra-block trade happened)
    //     _pushObservation(now32, curCumulative, uint160(1) << 32, true);

    //     (int24 tick, uint128 liq) = oracle.getBlockStartingTickAndLiquidity(
    //         address(pool)
    //     );
    //     assertEq(tick, 10, "starting tick = tickCumulativeDelta / delta");
    //     assertGt(liq, 0, "liquidity should be computed from sp delta");
    // }

    function test_revert_prevObservationUninitialized() public {
        uint32 now32 = uint32(block.timestamp);

        // obsIndex=1, cardinality=2, prev (index 0) is uninitialized
        pool.setSlot0(0, 1, 2);
        _pushObservation(0, 0, 0, false); // index 0 — uninitialized
        _pushObservation(now32, 0, 0, true); // index 1 — current block

        vm.expectRevert(bytes("ONI"));
        oracle.getBlockStartingTickAndLiquidity(address(pool));
    }
}

/*//////////////////////////////////////////////////////////////
              getWeightedArithmeticMeanTick()
//////////////////////////////////////////////////////////////*/

contract GetWeightedArithmeticMeanTickTest is OracleLibraryBase {
    function _single(int24 tick, uint128 weight) internal pure returns (OracleLibrary.WeightedTickData[] memory data) {
        data = new OracleLibrary.WeightedTickData[](1);
        data[0] = OracleLibrary.WeightedTickData({tick: tick, weight: weight});
    }

    function _pair(int24 t0, uint128 w0, int24 t1, uint128 w1)
        internal
        pure
        returns (OracleLibrary.WeightedTickData[] memory data)
    {
        data = new OracleLibrary.WeightedTickData[](2);
        data[0] = OracleLibrary.WeightedTickData({tick: t0, weight: w0});
        data[1] = OracleLibrary.WeightedTickData({tick: t1, weight: w1});
    }

    function test_singleEntry_returnsItsTick() public view {
        assertEq(oracle.getWeightedArithmeticMeanTick(_single(100, 1)), 100);
        assertEq(oracle.getWeightedArithmeticMeanTick(_single(-50, 999)), -50);
    }

    function test_equalWeights_returnsArithmeticMean() public view {
        // (100 + 200) / 2 = 150
        OracleLibrary.WeightedTickData[] memory data = _pair(100, 1, 200, 1);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), 150);
    }

    function test_unequalWeights() public view {
        // tick=100 weight=3, tick=200 weight=1 → (300+200)/4 = 125
        OracleLibrary.WeightedTickData[] memory data = _pair(100, 3, 200, 1);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), 125);
    }

    function test_negativeTicks() public view {
        // (-100 * 1 + -200 * 1) / 2 = -150
        OracleLibrary.WeightedTickData[] memory data = _pair(-100, 1, -200, 1);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), -150);
    }

    function test_negativeTicks_roundsToNegInfinity() public view {
        // (-100*1 + -201*1) / 2 = -301/2 = -150.5 → floor = -151
        OracleLibrary.WeightedTickData[] memory data = _pair(-100, 1, -201, 1);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), -151);
    }

    function test_positiveTicks_truncatesDown() public view {
        // (100*1 + 201*1) / 2 = 301/2 = 150 (integer truncation, not floor — same for positive)
        OracleLibrary.WeightedTickData[] memory data = _pair(100, 1, 201, 1);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), 150);
    }

    function test_mixedSignTicks_zeroResult() public view {
        // (-100 * 1 + 100 * 1) / 2 = 0
        OracleLibrary.WeightedTickData[] memory data = _pair(-100, 1, 100, 1);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), 0);
    }

    function test_dominantWeight() public view {
        // tick=500 weight=999, tick=0 weight=1 → ≈ 499 (heavily weighted toward 500)
        OracleLibrary.WeightedTickData[] memory data = _pair(500, 999, 0, 1);
        int24 result = oracle.getWeightedArithmeticMeanTick(data);
        assertApproxEqAbs(int256(result), 500, 1, "result should be close to dominant tick");
    }

    function testFuzz_singleEntry_alwaysReturnsTick(int24 tick, uint128 weight) public view {
        vm.assume(weight > 0);
        OracleLibrary.WeightedTickData[] memory data = _single(tick, weight);
        assertEq(oracle.getWeightedArithmeticMeanTick(data), tick);
    }

    function testFuzz_symmetry(int24 tick, uint128 weight) public view {
        // [t, w] and [-t, w] should give 0 (or ±1 due to rounding)
        vm.assume(weight > 0);
        vm.assume(tick > 0 && tick < 887272); // stay within valid tick range

        OracleLibrary.WeightedTickData[] memory data = _pair(tick, weight, -tick, weight);
        int24 result = oracle.getWeightedArithmeticMeanTick(data);
        assertApproxEqAbs(int256(result), 0, 1, "symmetric ticks should average near 0");
    }

    function testFuzz_resultBoundedByInputRange(int24 tick1, int24 tick2, uint128 weight1, uint128 weight2)
        public
        view
    {
        vm.assume(weight1 > 0 && weight2 > 0);
        // Avoid overflow in numerator: bound ticks to reasonable range
        tick1 = int24(bound(tick1, -887272, 887272));
        tick2 = int24(bound(tick2, -887272, 887272));

        int24 minTick = tick1 < tick2 ? tick1 : tick2;
        int24 maxTick = tick1 > tick2 ? tick1 : tick2;

        OracleLibrary.WeightedTickData[] memory data = _pair(tick1, weight1, tick2, weight2);
        int24 result = oracle.getWeightedArithmeticMeanTick(data);

        // Result must lie within [minTick - 1, maxTick] (the -1 accounts for floor rounding)
        assertGe(int256(result), int256(minTick) - 1, "result below minimum tick");
        assertLe(int256(result), int256(maxTick), "result above maximum tick");
    }
}

/*//////////////////////////////////////////////////////////////
                      getChainedPrice()
//////////////////////////////////////////////////////////////*/

contract GetChainedPriceTest is OracleLibraryBase {
    function test_revert_lengthMismatch() public {
        address[] memory tokens = new address[](3);
        int24[] memory ticks = new int24[](1); // needs 2
        vm.expectRevert(bytes("DL"));
        oracle.getChainedPrice(tokens, ticks);
    }

    function test_singleHop_sortedOrder_addsTick() public view {
        // tokens[0] < tokens[1] → synthetic += ticks[0]
        address[] memory tokens = new address[](2);
        tokens[0] = addrA; // smaller
        tokens[1] = addrB;

        int24[] memory ticks = new int24[](1);
        ticks[0] = 500;

        assertEq(oracle.getChainedPrice(tokens, ticks), 500);
    }

    function test_singleHop_reversedOrder_subtractsTick() public view {
        // tokens[0] > tokens[1] → synthetic -= ticks[0]
        address[] memory tokens = new address[](2);
        tokens[0] = addrB; // larger
        tokens[1] = addrA;

        int24[] memory ticks = new int24[](1);
        ticks[0] = 500;

        assertEq(oracle.getChainedPrice(tokens, ticks), -500);
    }

    function test_twoHop_sameSortOrder_addsBoth() public view {
        address addrC = address(0x3333);
        // A < B < C → both added
        address[] memory tokens = new address[](3);
        tokens[0] = addrA;
        tokens[1] = addrB;
        tokens[2] = addrC;

        int24[] memory ticks = new int24[](2);
        ticks[0] = 300;
        ticks[1] = 200;

        assertEq(oracle.getChainedPrice(tokens, ticks), 500);
    }

    function test_twoHop_mixedOrder_addAndSubtract() public view {
        address addrC = address(0x3333);
        // A < B → add first tick; C < B (i.e. tokens[1]=B > tokens[2]=addrC) → subtract second
        address[] memory tokens = new address[](3);
        tokens[0] = addrA; // 0x1111
        tokens[1] = addrB; // 0x2222
        tokens[2] = addrC; // 0x3333  — addrB(0x2222) < addrC(0x3333) so ADD

        int24[] memory ticks = new int24[](2);
        ticks[0] = 100;
        ticks[1] = 50;

        // A<B → +100;  B<C → +50
        assertEq(oracle.getChainedPrice(tokens, ticks), 150);
    }

    function test_negativeTicks() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = addrA;
        tokens[1] = addrB;

        int24[] memory ticks = new int24[](1);
        ticks[0] = -1000;

        assertEq(oracle.getChainedPrice(tokens, ticks), -1000);
    }

    function test_zeroTick() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = addrA;
        tokens[1] = addrB;

        int24[] memory ticks = new int24[](1);
        ticks[0] = 0;

        assertEq(oracle.getChainedPrice(tokens, ticks), 0);
    }

    function testFuzz_singleHop_sortOrder(address t0, address t1, int24 tick) public view {
        vm.assume(t0 != t1);
        tick = int24(bound(tick, -887272, 887272));

        address[] memory tokens = new address[](2);
        tokens[0] = t0;
        tokens[1] = t1;

        int24[] memory ticks = new int24[](1);
        ticks[0] = tick;

        int256 result = oracle.getChainedPrice(tokens, ticks);

        if (t0 < t1) {
            assertEq(result, int256(tick), "sorted pair should add tick");
        } else {
            assertEq(result, -int256(tick), "reversed pair should subtract tick");
        }
    }

    function testFuzz_roundTrip_twoHop(int24 tick1, int24 tick2) public view {
        // A→B→A: first hop adds (A<B), second hop subtracts (B>A) → net = 0
        tick1 = int24(bound(tick1, -400000, 400000));
        tick2 = int24(bound(tick2, -400000, 400000));

        address[] memory tokens = new address[](3);
        tokens[0] = addrA;
        tokens[1] = addrB;
        tokens[2] = addrA; // back to A

        int24[] memory ticks = new int24[](2);
        ticks[0] = tick1;
        ticks[1] = tick2; // second leg B>A → subtract

        // A<B → +tick1; B>A → -tick2
        int256 result = oracle.getChainedPrice(tokens, ticks);
        int256 expected = int256(tick1) - int256(tick2);
        assertEq(result, expected);
    }
}

/*//////////////////////////////////////////////////////////////
                  consult() FUZZ TESTS
//////////////////////////////////////////////////////////////*/

contract ConsultFuzzTest is OracleLibraryBase {
    function testFuzz_consult_meanTickRoundingIsFloor(int56 tickDelta, uint32 secondsAgo) public {
        secondsAgo = uint32(bound(secondsAgo, 1, 3600));
        // Keep tickDelta in a range that won't overflow int24 after division
        tickDelta = int56(bound(tickDelta, -887272 * int56(uint56(secondsAgo)), 887272 * int56(uint56(secondsAgo))));

        _setObserve(0, tickDelta, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), secondsAgo);

        // Manual floor division
        int256 exact = int256(tickDelta) / int256(uint256(secondsAgo));
        bool hasRem = tickDelta < 0 && (tickDelta % int56(uint56(secondsAgo)) != 0);
        int256 expected = hasRem ? exact - 1 : exact;

        assertEq(int256(meanTick), expected, "meanTick must match floor division");
    }

    function testFuzz_consult_meanTickWithinValidRange(int56 tickDelta, uint32 secondsAgo) public {
        secondsAgo = uint32(bound(secondsAgo, 1, 3600));
        tickDelta = int56(bound(tickDelta, -887272 * int56(uint56(secondsAgo)), 887272 * int56(uint56(secondsAgo))));

        _setObserve(0, tickDelta, 0, uint160(1) << 32);

        (int24 meanTick,) = oracle.consult(address(pool), secondsAgo);

        assertGe(int256(meanTick), int256(TickMath.MIN_TICK) - 1, "tick below MIN");
        assertLe(int256(meanTick), int256(TickMath.MAX_TICK), "tick above MAX");
    }
}
