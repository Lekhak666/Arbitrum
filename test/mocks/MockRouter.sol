// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockRouter {
    event SwapCalled(uint256 amountIn, address tokenIn, address tokenOut, address to);

    function swapExactTokensForTokens(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        emit SwapCalled(amountIn, path[0], path[1], to);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
}
