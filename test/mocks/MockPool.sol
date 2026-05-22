// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockPool {
    int24 public tick;

    constructor(int24 _tick) {
        tick = _tick;
    }

    function observe(
        uint32[] calldata
    ) external view returns (int56[] memory tickCumulatives, uint160[] memory) {
        tickCumulatives = new int56[](2);

        tickCumulatives[0] = 0;
        tickCumulatives[1] = int56(tick) * 1800;

        return (tickCumulatives, new uint160[](2));
    }
}
