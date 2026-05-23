// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {MockUniswapV3Pool} from "../mocks/MockUniswapV3Pool.sol";

contract MockUniswapV3PoolTest is Test {
    MockUniswapV3Pool internal pool;

    function setUp() public {
        pool = new MockUniswapV3Pool();
    }

    /*//////////////////////////////////////////////////////////////
                            UNIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSlot0() public {
        pool.setSlot0(100, 5, 10);

        (, int24 tick, uint16 idx, uint16 card,,,) = pool.slot0();

        assertEq(tick, 100);
        assertEq(idx, 5);
        assertEq(card, 10);
    }

    function test_SetLiquidity() public {
        pool.setLiquidity(123456);

        assertEq(pool.liquidity(), 123456);
    }

    function test_PushObservation() public {
        pool.pushObservation(1000, 500, 999, true);

        (uint32 ts, int56 tickCum, uint160 secLiq, bool initialized) = pool.observation(0);

        assertEq(ts, 1000);
        assertEq(tickCum, 500);
        assertEq(secLiq, 999);
        assertTrue(initialized);
    }

    function test_ClearObservations() public {
        pool.pushObservation(1, 2, 3, true);
        pool.clearObservations();

        vm.expectRevert();
        pool.observation(0);
    }

    function test_SetObserveData() public {
        int56[] memory ticks = new int56[](2);
        uint160[] memory liqs = new uint160[](2);

        ticks[0] = 100;
        ticks[1] = 200;

        liqs[0] = 10;
        liqs[1] = 20;

        pool.setObserveData(ticks, liqs);

        (int56[] memory rt, uint160[] memory rl) = pool.observe(new uint32[](2));

        assertEq(rt.length, 2);
        assertEq(rl.length, 2);

        assertEq(rt[0], 100);
        assertEq(rt[1], 200);

        assertEq(rl[0], 10);
        assertEq(rl[1], 20);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetSlot0(int24 tick, uint16 idx, uint16 card) public {
        pool.setSlot0(tick, idx, card);

        (, int24 rt, uint16 ri, uint16 rc,,,) = pool.slot0();

        assertEq(rt, tick);
        assertEq(ri, idx);
        assertEq(rc, card);
    }

    function testFuzz_SetLiquidity(uint128 liq) public {
        pool.setLiquidity(liq);

        assertEq(pool.liquidity(), liq);
    }

    function testFuzz_PushObservation(uint32 ts, int56 tickCum, uint160 secLiq, bool init) public {
        pool.pushObservation(ts, tickCum, secLiq, init);

        (uint32 rts, int56 rtc, uint160 rsl, bool ri) = pool.observation(0);

        assertEq(rts, ts);
        assertEq(rtc, tickCum);
        assertEq(rsl, secLiq);
        assertEq(ri, init);
    }

    function testFuzz_SetObserveData(int56 a, int56 b, uint160 c, uint160 d) public {
        int56[] memory ticks = new int56[](2);
        uint160[] memory liqs = new uint160[](2);

        ticks[0] = a;
        ticks[1] = b;

        liqs[0] = c;
        liqs[1] = d;

        pool.setObserveData(ticks, liqs);

        (int56[] memory rt, uint160[] memory rl) = pool.observe(new uint32[](2));

        assertEq(rt[0], a);
        assertEq(rt[1], b);

        assertEq(rl[0], c);
        assertEq(rl[1], d);
    }
}

/*//////////////////////////////////////////////////////////////
                        INVARIANT TESTING
//////////////////////////////////////////////////////////////*/

contract PoolHandler {
    MockUniswapV3Pool internal pool;

    constructor(MockUniswapV3Pool _pool) {
        pool = _pool;
    }

    function setSlot0(int24 tick, uint16 idx, uint16 card) external {
        pool.setSlot0(tick, idx, card);
    }

    function setLiquidity(uint128 liq) external {
        pool.setLiquidity(liq);
    }

    function pushObservation(uint32 ts, int56 tc, uint160 spl, bool init) external {
        pool.pushObservation(ts, tc, spl, init);
    }

    function clear() external {
        pool.clearObservations();
    }
}

contract MockUniswapV3PoolInvariant is StdInvariant, Test {
    MockUniswapV3Pool internal pool;
    PoolHandler internal handler;

    function setUp() public {
        pool = new MockUniswapV3Pool();
        handler = new PoolHandler(pool);

        targetContract(address(handler));
    }

    /// liquidity should always match getter storage
    function invariant_LiquidityConsistent() public view {
        assertEq(pool.liquidity(), pool.liquidityValue());
    }

    /// slot0 cardinality mirrors public storage
    function invariant_Slot0Consistent() public view {
        (, int24 tick, uint16 idx, uint16 card,,,) = pool.slot0();

        assertEq(tick, pool.slot0Tick());
        assertEq(idx, pool.observationIndex());
        assertEq(card, pool.observationCardinality());
    }
}
