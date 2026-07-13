// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}
