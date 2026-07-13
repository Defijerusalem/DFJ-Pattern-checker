// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ISRDHooks {
    function on_transfer(
        address caller,
        address from,
        address to,
        uint256 supply,
        uint256 prevStakedFrom,
        uint256 prevStakedTo,
        uint256 value
    ) external;

    function on_stake(
        address caller,
        address account,
        uint256 prevSupply,
        uint256 prevStaked,
        uint256 value
    ) external;

    function on_unstake(
        address account,
        uint256 prevSupply,
        uint256 prevStaked,
        uint256 value
    ) external;
}

/// @notice Stand-in for the real stYFI-style staking token + hook-calling depositor,
/// combined. Real balances live here; every mutation calls the corresponding real
/// SRD hook with the exact prev-state parameters the real system would supply.
contract MockStakingSystem {
    ISRDHooks public immutable srd;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    constructor(address _srd) {
        srd = ISRDHooks(_srd);
    }

    function stake(address account, uint256 amount) external {
        uint256 prevSupply = totalSupply;
        uint256 prevStaked = balanceOf[account];
        balanceOf[account] = prevStaked + amount;
        totalSupply = prevSupply + amount;
        srd.on_stake(msg.sender, account, prevSupply, prevStaked, amount);
    }

    function unstake(address account, uint256 amount) external {
        uint256 prevSupply = totalSupply;
        uint256 prevStaked = balanceOf[account];
        require(prevStaked >= amount, "insufficient staked");
        balanceOf[account] = prevStaked - amount;
        totalSupply = prevSupply - amount;
        srd.on_unstake(account, prevSupply, prevStaked, amount);
    }

    function transferStake(address from, address to, uint256 amount) external {
        uint256 supply = totalSupply;
        uint256 prevStakedFrom = balanceOf[from];
        uint256 prevStakedTo = balanceOf[to];
        require(prevStakedFrom >= amount, "insufficient staked");
        balanceOf[from] = prevStakedFrom - amount;
        balanceOf[to] = prevStakedTo + amount;
        srd.on_transfer(msg.sender, from, to, supply, prevStakedFrom, prevStakedTo, amount);
    }
}
