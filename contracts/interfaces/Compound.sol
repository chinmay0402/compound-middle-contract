// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface CErc20 {
    function mint(uint256) external returns (uint256);

    function exchangeRateCurrent() external returns (bool);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function borrow(uint256) external returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function borrowBalanceCurrent(address) external view returns (uint256); // current borrowed amount + due interest

    function repayBorrow(uint256) external returns (uint256);
}

interface CEth {
    function mint() external payable; // to deposit to compound

    function redeem(uint256) external returns (uint256); // to withdraw from compound on basis of cEth tokens

    function redeemUnderlying(uint256) external returns (uint256); // to withdraw from compound on basis of underlying asset amount

    function exchangeRateCurrent() external returns (uint256);

    function balanceOf(address) external view returns (uint256); // to get balance of cEth tokens of the contract

    function borrow(uint256) external returns (uint256);

    function borrowBalanceCurrent(address) external returns (uint256);

    function repayBorrow() external payable; // payable since receives eth
}

interface Comptroller {
    // Comptroller is the risk-management layer of the (Compound) protocol
    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata)
        external
        returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

interface PriceFeed {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}
