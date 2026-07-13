// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Re-exported so YearnBoostedStaker.sol's unmodified `import {IERC20, SafeERC20} from "./SafeERC20.sol"`
// resolves to the standard, real OpenZeppelin implementations.
