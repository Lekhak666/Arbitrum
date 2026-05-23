// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {OracleLibrary} from "../../src/libraries/OracleLibrary.sol";

contract MockPool {
    int56[2] public tickCums;
    uint160[2] public liqCums;

    uint16 public obsIndex;
    uint16 public obsCardinality;
    int24 public slotTick;
    uint128 public liq;

    struct Obs {
        uint32 ts;
        int56 tickCum;
        uint160 liqCum;
        bool init;
    }

    mapping(uint256 => Obs) public obs;

    function setObserve(int56 a, int56 b, uint160 c, uint160 d) external {
        tickCums = [a, b];
        liqCums = [c, d];
    }

    function observe(uint32[] calldata) external view returns (int56[] memory tc, uint160[] memory lc) {
        tc = new int56[](2);
        lc = new uint160[](2);

        tc[0] = tickCums[0];
        tc[1] = tickCums[1];

        lc[0] = liqCums[0];
        lc[1] = liqCums[1];
    }

    function setSlot(int24 t, uint16 i, uint16 c) external {
        slotTick = t;
        obsIndex = i;
        obsCardinality = c;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (0, slotTick, obsIndex, obsCardinality, 0, 0, false);
    }

    function setObs(uint256 i, uint32 ts, int56 tc, uint160 lc, bool init) external {
        obs[i] = Obs(ts, tc, lc, init);
    }

    function observations(uint256 i) external view returns (uint32, int56, uint160, bool) {
        Obs memory o = obs[i];
        return (o.ts, o.tickCum, o.liqCum, o.init);
    }

    function liquidity() external view returns (uint128) {
        return liq;
    }

    function setLiquidity(uint128 num) external {
        liq = num;
    }
}

contract OracleHarness {
    function consult(address p, uint32 s) external view returns (int24, uint128) {
        return OracleLibrary.consult(p, s);
    }

    function quote(int24 t, uint128 b, address x, address y) external pure returns (uint256) {
        return OracleLibrary.getQuoteAtTick(t, b, x, y);
    }

    function oldest(address p) external view returns (uint32) {
        return OracleLibrary.getOldestObservationSecondsAgo(p);
    }

    function blockStart(address p) external view returns (int24, uint128) {
        return OracleLibrary.getBlockStartingTickAndLiquidity(p);
    }

    function weighted(OracleLibrary.WeightedTickData[] memory d) external pure returns (int24) {
        return OracleLibrary.getWeightedArithmeticMeanTick(d);
    }

    function chained(address[] memory t, int24[] memory x) external pure returns (int256) {
        return OracleLibrary.getChainedPrice(t, x);
    }
}

contract OracleLibraryBranchesTest is Test {
    MockPool internal pool;
    OracleHarness internal h;

    function setUp() public {
        pool = new MockPool();
        h = new OracleHarness();
    }

    function test_consult_reverts_zero() public {
        vm.expectRevert(bytes("BP"));
        h.consult(address(pool), 0);
    }

    function test_consult_negative_round_branch() public {
        pool.setObserve(-11, 0, 1, 2);

        (int24 tick,) = h.consult(address(pool), 10);

        assertEq(tick, 1);
    }

    function test_oldest_revert_NI() public {
        pool.setSlot(0, 0, 0);

        vm.expectRevert(bytes("NI"));
        h.oldest(address(pool));
    }

    // function test_oldest_fallback_to_zero() public {
    //     pool.setSlot(0, 0, 2);

    //     pool.setObs(1, uint32(block.timestamp - 10), 0, 0, false);
    //     pool.setObs(0, uint32(block.timestamp - 20), 0, 0, true);

    //     assertEq(h.oldest(address(pool)), 20);
    // }

    function test_blockStart_revert_NEO() public {
        pool.setSlot(0, 0, 1);

        vm.expectRevert(bytes("NEO"));
        h.blockStart(address(pool));
    }

    function test_blockStart_early_return() public {
        pool.setSlot(7, 0, 2);
        pool.setObs(0, uint32(block.timestamp - 1), 0, 0, true);
        pool.setLiquidity(99);

        (int24 t, uint128 num) = h.blockStart(address(pool));

        assertEq(t, 7);
        assertEq(num, 99);
    }

    function test_blockStart_ONI() public {
        pool.setSlot(0, 1, 2);

        pool.setObs(1, uint32(block.timestamp), 100, 100, true);
        pool.setObs(0, uint32(block.timestamp - 1), 90, 90, false);

        vm.expectRevert(bytes("ONI"));
        h.blockStart(address(pool));
    }

    function test_weighted_negative_rounding() public view {
        OracleLibrary.WeightedTickData[] memory d = new OracleLibrary.WeightedTickData[](2);

        d[0] = OracleLibrary.WeightedTickData(-5, 1);
        d[1] = OracleLibrary.WeightedTickData(0, 2);

        assertEq(h.weighted(d), -2);
    }

    function test_chained_DL() public {
        address[] memory t = new address[](2);
        int24[] memory x = new int24[](2);

        vm.expectRevert(bytes("DL"));
        h.chained(t, x);
    }

    function test_chained_add_sub_branches() public view {
        address[] memory t = new address[](3);
        int24[] memory x = new int24[](2);

        t[0] = address(1);
        t[1] = address(2);
        t[2] = address(1);

        x[0] = 10;
        x[1] = 3;

        assertEq(h.chained(t, x), 7);
    }

    function test_quote_both_paths() public view {
        h.quote(0, 1e18, address(1), address(2));
        h.quote(500000, 1e18, address(2), address(1));
    }
}
