// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Helpers } from "./helpers.sol";

contract CompoundMiddleContract is Helpers {
    using SafeERC20 for IERC20;

    address private owner; // required to send the received eth back to the user
    uint256 private ethBorrowBalance;

    constructor() {
        owner = msg.sender; // sets contract owner
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    /**
     * @dev deposits tokens/ETH to Compound protocol
     * @param _tokenAddress address of the token which is to be deposited (ethAddr for ETH deposits)
     * @param _cTokenAddress address of the cToken contract of the token Compound
     * @param _amount number of tokens/ETH (in Wei) to deposit
     */
    function deposit(
        address _tokenAddress, 
        address payable _cTokenAddress, 
        uint256 _amount
    ) public payable {
        // create reference to cEther contract in Compound
        // msg.value is the amount of ether send to the contract from the wallet when this function was called
        if(_tokenAddress == ethAddr){
            cEth.mint{value: _amount, gas: 250000}(); // no return, will revert on error
            console.log("Supplied %s wei to Compound via smart contract",_amount);
            console.log("Total ether deposits: ", cEth.balanceOfUnderlying(address(this)));
        }
        else{
            IERC20 token = IERC20(_tokenAddress);
            CErc20 cToken = CErc20(_cTokenAddress);

            token.safeTransferFrom(owner, address(this), _amount);
            // Approve transfer on the ERC20 contract

            token.safeApprove(_cTokenAddress, _amount);

            // supply the tokens to Compound and mint cTokens
            require(cToken.mint(_amount) == 0, "TOKEN DEPOSIT FAILED");

            console.log("Total token deposits: ", cToken.balanceOfUnderlying(address(this)));
        }

        enterMarket(_cTokenAddress);
    }

    /**
     * @dev withdraws ether deposited to compound
            uses redeem() and redeemUnderlying() methods in CEth contract
     * @param _redeemAmount the number of cTokens to be redeemed
     * @param _cTokenAddress address of cToken contract on Compound
     * @param _tokenAddress address of ERC20 token to be withdrawn (ethAddr for ETH withdrawals)
     */
    function withdraw(
        uint256 _redeemAmount, 
        address _cTokenAddress, 
        address _tokenAddress
    )external {
        if(_tokenAddress == ethAddr) {
            require(cEth.balanceOf(address(this)) >= _redeemAmount, "INSUFFICIENT cTOKEN BALANCE");

            require(cEth.redeem(_redeemAmount) == 0, "ERROR WHILE REDEEMING"); // redeem tokens

            uint256 amountOfEthreceived = _redeemAmount * cEth.exchangeRateCurrent();
            console.log("Redeemed %s cEth for %s wei", _redeemAmount, amountOfEthreceived);

            // send recieved eth back to user
            (bool success, ) = owner.call{value: address(this).balance}(""); // prefer call() instead of transfer()
            // transfer() and send() were the functions used earlier, but they forward fixed gas stipends (2300)
            // there have been some breaking changes since then and assuming fixed gas costs is no longer feasible
            // so, call() is the correct way to send funds these days
            require(success, "FAILURE IN SENDING ETHER TO USER");
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            IERC20 token = IERC20(_tokenAddress);

            require(cToken.balanceOf(address(this)) >= _redeemAmount, "INSUFFICIENT cTOKEN BALANCE");

            require(cToken.redeem(_redeemAmount) == 0, "ERROR WHILE REDEEMING");

            // transfer erc20 tokens back to user
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }
    }

    /**
     * @dev borrows Eth from Compound keeping another token as collateral
     * @param _tokenAddress address of token to borrow (ethAddr for ETH borrows)
     * @param _cTokenAddress address of cToken contract for the token being borrowed
     * @param _amountToBorrow amount of ether to be borrowed in wei
    */
    function borrow(
        address _tokenAddress,
        address _cTokenAddress,
        uint256 _amountToBorrow
    ) external {

        checkCollateral(_cTokenAddress, _amountToBorrow);

        if(_tokenAddress == ethAddr) {

            require(cEth.borrow(_amountToBorrow) == 0, "BORROW FAILED");

            console.log("Borrowed %s wei", _amountToBorrow);

            (bool success, ) = owner.call{value: _amountToBorrow}("");
            require(success, "FAILURE IN SENDING ETHER TO USER");
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            IERC20 token = IERC20(_tokenAddress);
            
            // borrow
            require(cToken.borrow(_amountToBorrow) == 0, "BORROW FAILED");

            // transfer borrowed erc20 to user
            token.safeTransfer(owner, _amountToBorrow);
        }
    }

    /**
     * @dev repays borrowed eth
     * @param _cEtherAddress address of the cEth contract in Compound
     * @return uint256 updated borrow balance of the user
    */
    function paybackEth(address _cEtherAddress, uint256 gas)
        external
        payable
        returns (uint256)
    {
        CEth cEth = CEth(_cEtherAddress);
        // CHECK: IF msg.value ETH WAS EVEN BORROWED
        require(
            msg.value <= cEth.borrowBalanceCurrent(address(this)),
            "REPAY AMOUNT MORE THAN BORROWED AMOUNT"
        );

        cEth.repayBorrow{value: msg.value, gas: gas}();

        console.log("Repayed %s ether", msg.value);
        ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
        return ethBorrowBalance;
    }

    /**
     * @dev borrows Eth from Compound keeping another eth as collateral, used by Leverage contract
     * @param _cEtherAddress address of the cEther contract in Compound
     * @param _amountToBorrowInWei amount of ether to be borrowed in wei
     * @return uint256 the current borrow balance of the user
     */
    function _leverageEth(
        address payable _cEtherAddress,
        uint256 _amountToBorrowInWei
    ) external returns (uint256) {
        checkCollateral(cEtherAddress, _amountToBorrowInWei);

        require(cEth.borrow(_amountToBorrowInWei) == 0, "BORROW FAILED");

        console.log("Borrowed %s wei", _amountToBorrowInWei);

        uint256 borrowBalance = cEth.borrowBalanceCurrent(address(this));

        // send ether to Leverage contract
        // (bool success, ) = _leverageContractAddress.call{ value: address(this).balance }("");
        // require(success, "FAILURE IN SENDING ETHER TO LEVERAGE CONTRACT");
        deposit(ethAddr, _cEtherAddress, address(this).balance);

        return borrowBalance;
    }

    function getEthBorrowBalance() external view returns (uint256) {
        return ethBorrowBalance;
    }

    /**
     * @dev borrows erc20 token with the same token as collateral (used for leveraging)
     * @param _cTokenAddress address of cToken contract in Compound (which is to be lleveraged)
     * @param _erc20ToLeverageAddress address of erc20 token contract
     * @param _amountToBorrow amount of erc20 tokens to borrow
     * @return uint256 borrowBalance of the user
     */
    function _leverageErc20(
        address _cTokenAddress,
        address _erc20ToLeverageAddress,
        uint256 _amountToBorrow
    ) external returns (uint256) {
        // Create references to Compound and Token contracts
        CErc20 cToken = CErc20(_cTokenAddress);
        
        checkCollateral(_cTokenAddress, _amountToBorrow);

        // borrow
        require(cToken.borrow(_amountToBorrow) == 0, "BORROW FAILED");

        // transfer borrowed erc20 to user
        deposit(_erc20ToLeverageAddress, payable(_cTokenAddress), _amountToBorrow);

        return cToken.borrowBalanceCurrent(address(this));
    }

    /**
     * @dev repays erc20 tokens to Compound
     * @param _cErc20Address address of cErc20 contract in Compound
     * @param _erc20Address address of the erc20 token contract
     * @param _repayAmount number of erc20 tokens to be repayed
     * @return uint256 updated borrowBalance for the erc20 token
     */
    function paybackErc20(
        address _cErc20Address,
        address _erc20Address,
        uint256 _repayAmount
    ) external returns (uint256) {
        // create references to contracts
        CErc20 cToken = CErc20(_cErc20Address);
        IERC20 token = IERC20(_erc20Address);

        // transfer user's tokens to contract
        token.safeTransferFrom(msg.sender, address(this), _repayAmount);

        // approve Compound to spend erc20 tokens
        token.safeIncreaseAllowance(_cErc20Address, _repayAmount);

        // CHECK: IF USER HAS A BORROWBALANCE OF MORE THAN _repayAmount ON THIS TOKEN
        require(
            cToken.borrowBalanceCurrent(address(this)) >= _repayAmount,
            "REPAY AMOUNT MORE THAN BORROWED AMOUNT"
        );

        // repay borrow
        require(cToken.repayBorrow(_repayAmount) == 0, "REPAY FAILED");

        // return updated borrowBalance
        return cToken.borrowBalanceCurrent(address(this));
    }

    /**
     *@dev returns the total value of all deposited collateral in USD (scaled up by 10**36)
     */
    function getTotalCollateralInUsd()
        external
        returns (uint256) {
        address[] memory markets = comptroller.getAssetsIn(address(this));
        uint256 totalCollateral = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            CErc20 cToken = CErc20(markets[i]);
            UniswapAnchoredView priceFeed = UniswapAnchoredView(0x046728da7cb8272284238bD3e47909823d63A58D);
            uint256 amountOfTokenDepositsInUsd = priceFeed.getUnderlyingPrice(markets[i]) * cToken.balanceOfUnderlying(address(this));
            totalCollateral = totalCollateral + amountOfTokenDepositsInUsd;
        }
        console.log(
            "Total Collateral in USD (scaled up by 10^36): ",
            totalCollateral
        );
        return totalCollateral; //  this value has actually been scaled by 1e36
    }

    function getTotalDebtInUsd() external returns (uint256) {
        address[] memory markets = comptroller.getAssetsIn(address(this));
        uint256 totalDebt = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            CErc20 cToken = CErc20(markets[i]);
            UniswapAnchoredView priceFeed = UniswapAnchoredView(0x046728da7cb8272284238bD3e47909823d63A58D);
            uint256 amountBorrowedInUsd = priceFeed.getUnderlyingPrice(markets[i]) * cToken.borrowBalanceCurrent(address(this));
            totalDebt = totalDebt + amountBorrowedInUsd;
        }
        console.log("Total Debt in USD (scaled up by 10^36): ", totalDebt);
        return totalDebt; //  this value has actually been scaled by 1e36
    }

    /**
     *@dev fallback function to accept ether when borrowEth is called and send the eth back to owner
    */
    receive() external payable {}
}
