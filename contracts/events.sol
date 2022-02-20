// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract Events {
    event LogDeposit(
        address indexed token,
        address cToken,
        uint256 amount
    );

    event LogWithdraw(
        address indexed token,
        address cToken,
        uint256 amount
    );

    event LogBorrow(
        address indexed token,
        address cToken,
        uint256 amount
    );

    event LogRepay(
        address indexed token,
        address cToken,
        uint256 amount
    );
    
    event LogLeverage(
        address indexed token,
        address cToken,
        uint256 amount
    );
}