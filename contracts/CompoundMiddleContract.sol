// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";

interface Erc20 {
    function approve(address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);
}

interface CErc20 {
    function mint(uint256) external returns (uint256);

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

contract CompoundMiddleContract {
    address cEtherContract = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // address of the cEtherContract on Ethereum Mainnet

    /**
     * @dev deposits Ether to Compound protocol
            uses the mint() method in CEth contract
     * @return bool denoting status of transaction (success/failure)
     */
    // function receives ether from the wallet of the user, thus payable
    function depositEth(address payable _cEtherAddress)
        external
        payable
        returns (bool)
    {
        // create reference to cEther contract in Compound
        CEth cEth = CEth(_cEtherAddress);

        // msg.value is the amount of ether send to the contract from the wallet when this function was called
        cEth.mint{value: msg.value, gas: 250000}();
        console.log(
            "Supplied %s ETH to Compound via smart contract",
            msg.value / 1e18
        );
        console.log(
            "cEth balance of contract: ",
            cEth.balanceOf(address(this)) / 1e8
        );
        return true;
    }

    /**
     * @dev withdraws ether deposited to compound
            uses redeem() and redeemUnderlying() methods in CEth contract
     * @param _redeemAmount depending upon _redeemType, the number of cTokens or the amount of underlying assest to be redeemed
     * @param _redeemType basis on which eth is to be redeemed (can be 0 or 1)
                          0 denotes that the parameter _redeemAmount denotes the nubmer of cTokens that are to be redeemed
                          1 denotes that the parameter _redeemAmount denotes the amount of underlying assest that is to be redeemed
     * @return bool status of transaction
     */
    function withdrawEth(
        uint256 _redeemAmount,
        uint256 _redeemType,
        address _cEtherAddress
    ) external returns (bool) {
        CEth cEth = CEth(_cEtherAddress);

        uint256 redeemResult;

        if (_redeemType == 1) {
            require(
                cEth.balanceOf(address(this)) >= _redeemAmount,
                "NOT ENOUGH cTOKENS"
            );
            redeemResult = cEth.redeem(_redeemAmount);
            uint256 amountOfEthreceived = _redeemAmount *
                cEth.exchangeRateCurrent();
            console.log(
                "Redeemed %s cEth for %s ether",
                _redeemAmount,
                amountOfEthreceived
            );
        } else {
            uint256 cTokensRedeemed = _redeemAmount /
                cEth.exchangeRateCurrent();
            require(
                cTokensRedeemed >= cEth.balanceOf(address(this)),
                "NOT ENOUGH cTOKENS"
            );
            redeemResult = cEth.redeemUnderlying(_redeemAmount);
            console.log(
                "received %s ether for %s cEth",
                _redeemAmount,
                cTokensRedeemed
            );
        }

        return redeemResult == 0 ? true : false;
    }

    /**
     * @dev borrows Eth from Compound keeping another token as collateral
     * @param _cEtherAddress address of the cEther contract in Compound
     * @param _comptrollerAddress address of the comptroller contract in Compound
     * @param _cTokenAddress address of the cToken contract in Compound
     * @param _underlyingAddress address of contract of the token to be supplied as collateral
     * @param _underlyingToSupplyAsCollateral amount of tokens to supply as collateral
     * @return uint256 the current borrow balance of the user
     */
    function borrowEth(
        address payable _cEtherAddress,
        address _comptrollerAddress,
        address _cTokenAddress,
        address _underlyingAddress,
        uint256 _underlyingToSupplyAsCollateral
    ) public returns (uint256) {
        // declare references to external contracts
        CEth cEth = CEth(_cEtherAddress);
        Comptroller comptroller = Comptroller(_comptrollerAddress);
        CErc20 cToken = CErc20(_cTokenAddress);
        Erc20 underlying = Erc20(_underlyingAddress);

        // supply collateral
        underlying.approve(_cTokenAddress, _underlyingToSupplyAsCollateral);
        uint256 error = cToken.mint(_underlyingToSupplyAsCollateral);
        require(error == 0, "cERC20 MINT ERROR");

        // enter the market with the cTokens received (to make the above supplied tokens collateral)
        address[] memory cTokens = new address[](1); // 1 is the array length
        // cTokens is the list of tokens for which the market is to be entered
        cTokens[0] = _cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets FAILED");

        console.log(
            "Placed %s tokens (%s) as collateral",
            _underlyingToSupplyAsCollateral,
            _underlyingAddress
        );

        (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));
        require(error2 == 0, "comptroller.getAccountLiquidity FAILED");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        console.log("Liquidity available", liquidity); // liquidity is the USD value borrowable by the user, before it reaches liquidation

        // borrow
        uint256 amountToBorrowInWei = 2000000000000000; // CHANGE
        cEth.borrow(amountToBorrowInWei);
        uint256 borrowBalance = cEth.borrowBalanceCurrent(address(this));

        console.log("Borrowed %s eth", amountToBorrowInWei / 18);

        return borrowBalance;
    }

    /**
     * @dev repays borrowed eth
     * @param _cEtherAddress address of the cEth contract in Compound
     * @param amount amount of ether to be repayed
     * @return bool status of transaction
     */
    function paybackEth(address _cEtherAddress, uint256 amount)
        public
        returns (bool)
    {
        CEth cEth = CEth(_cEtherAddress);
        cEth.repayBorrow{value: amount}();

        console.log("Repayed %s ether", amount);

        return true;
    }

    /**
     *@dev fallback function to accept ether when borrowEth is called
     */
    receive() external payable {}
}
