// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOracle {
    function getPrice(address tokenIn, address tokenOut) external view returns (uint256);
}
