// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "./interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Helpers } from "./helpers.sol";
import { Events } from "./events.sol";

contract CompoundMiddleContract is Helpers, Events {
    using SafeERC20 for IERC20;

    address private owner; // required to send the received eth back to the user
    uint256 private ethBorrowBalance;

    constructor() {
        owner = msg.sender; // sets contract owner
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function getEthBorrowBalance() external view returns (uint256) {
        return ethBorrowBalance;
    }

    /**
     * @notice deposits tokens/ETH to Compound protocol
     * @dev uses mint() function in Compound protocol, uses ethAddr for ether deposits
     * @param _tokenAddress address of the token which is to be deposited (ethAddr for ETH deposits)
     * @param _cTokenAddress address of the cToken contract of the token Compound
     * @param _amt number of tokens/ETH (in Wei) to deposit, uint(-1) for max. amount
     * @param getId ID to retrieve amt.
     * @param setId ID stores the amount of tokens deposited.
    */
    function deposit(
        address _tokenAddress, 
        address payable _cTokenAddress, 
        uint256 _amt,
        uint getId, 
        uint setId
    ) public payable returns (string memory _eventName, bytes memory _eventParam) {
        uint _amount = getUint(getId, _amt);

        if(_tokenAddress == ethAddr){
            if(_amount == type(uint).max) _amount = address(this).balance;

            cEth.mint{value: _amount}(); // no return, will revert on error
            console.log("Supplied %s wei to Compound via smart contract",_amount);
            console.log("Total ether deposits: ", cEth.balanceOfUnderlying(address(this)));
        }
        else{
            IERC20 token = IERC20(_tokenAddress);
            CErc20 cToken = CErc20(_cTokenAddress);

            if(_amount == type(uint).max) _amount = token.balanceOf(address(this));
            
            // Approve transfer on the ERC20 contract
            token.safeApprove(_cTokenAddress, _amount);

            // supply the tokens to Compound and mint cTokens
            require(cToken.mint(_amount) == 0, "TOKEN DEPOSIT FAILED");

            console.log("Total token deposits: ", cToken.balanceOfUnderlying(address(this)));
        }
        enterMarket(_cTokenAddress);

        setUint(setId, _amount);

        _eventName = "LogDeposit(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _amount);
    }

    /**
     * @notice withdraws tokens deposited to compound by taking amount of cTokens to be redeemed as input
     * @dev uses redeem() function in Compound contract
     * @param _cTokenAmount the number of cTokens to be redeemed
     * @param _cTokenAddress address of cToken contract on Compound
     * @param _tokenAddress address of ERC20 token to be withdrawn (ethAddr for ETH withdrawals)
     * @param getId ID to retrieve amt.
     * @param setId ID stores the amount of tokens deposited.
    */
    function withdraw(
        uint256 _cTokenAmount, 
        address _cTokenAddress, 
        address _tokenAddress,
        uint256 getId,
        uint256 setId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        uint256 _amt = getUint(getId, _cTokenAmount);
        uint withdrawAmount = 0;
        if(_tokenAddress == ethAddr) {
            if(_amt == type(uint).max)_amt = cEth.balanceOf(address(this));

            require(cEth.balanceOf(address(this)) >= _amt, "INSUFFICIENT cTOKEN BALANCE");

            uint initialAmount = address(this).balance;

            require(cEth.redeem(_amt) == 0, "ERROR WHILE REDEEMING"); // redeem tokens

            uint finalAmount = address(this).balance;
            withdrawAmount = finalAmount - initialAmount;

            uint256 amountOfEthreceived = _amt * cEth.exchangeRateCurrent();
            console.log("Redeemed %s cEth for %s wei", _amt, amountOfEthreceived);
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            IERC20 token = IERC20(_tokenAddress);
            if(_amt == type(uint).max){
                _amt = cToken.balanceOf(address(this));
            }

            require(cToken.balanceOf(address(this)) >= _amt, "INSUFFICIENT cTOKEN BALANCE");

            uint initialAmount = token.balanceOf(address(this));

            require(cToken.redeem(_amt) == 0, "ERROR WHILE REDEEMING");

            uint finalAmount = token.balanceOf(address(this));
            withdrawAmount = finalAmount - initialAmount;
        }
        setUint(setId, withdrawAmount);
        _eventName = "LogWithdraw(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _amt);
    }

    /**
     * @notice borrows tokens/ETH from Compound using deposits as collateral
     * @dev uses all current deposits as collateral (to calculate liquidity), updates ethBorrowBalance after borrow
     * @param _tokenAddress address of token to borrow (ethAddr for ETH borrows)
     * @param _cTokenAddress address of cToken contract for the token being borrowed
     * @param _amountToBorrow amount to be borrowed
     * @param getId ID to retrieve amt.
     * @param setId ID stores the amount of tokens deposited.
    */
    function borrow(
        address _tokenAddress,
        address _cTokenAddress,
        uint256 _amountToBorrow,
        uint256 getId,
        uint256 setId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        uint _amt = getUint(getId, _amountToBorrow);
        checkCollateral(_cTokenAddress, _amt);

        if(_tokenAddress == ethAddr) {
            require(cEth.borrow(_amt) == 0, "BORROW FAILED");

            console.log("Borrowed %s wei", _amt);
            ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            // borrow
            require(cToken.borrow(_amt) == 0, "BORROW FAILED");
        }

        setUint(setId, _amt);
        _eventName = "LogBorrow(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _amt);
    }

    /**
     * @notice repays borrowed tokens
     * @dev updates ethBorrowBalance
     * @param _cTokenAddress address of the cToken contract in Compound
     * @param _tokenAddress address of token contract (ethAddr for ETH)
     * @param _repayAmount amount of token to be repayed
     * @param getId ID to retrieve amt.
     * @param setId ID stores the amount of tokens deposited.
    */
    function repay(
        address _cTokenAddress, 
        address _tokenAddress,
        uint256 _repayAmount,
        uint256 getId,
        uint256 setId
    ) external payable returns (string memory _eventName, bytes memory _eventParam) {
        uint _amt = getUint(getId, _repayAmount);
        if(_tokenAddress == ethAddr) {
            
            if(_amt == type(uint).max)_amt = cEth.borrowBalanceCurrent(address(this)); 
        
            // CHECK: IF msg.value ETH WAS EVEN BORROWED 
            ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
            require(_amt <= ethBorrowBalance,"REPAY AMOUNT MORE THAN BORROWED AMOUNT");
            
            cEth.repayBorrow{value: _repayAmount}();

            console.log("Repayed %s wei", msg.value);
            ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            IERC20 token = IERC20(_tokenAddress);

            if(_amt == type(uint).max)_amt = cToken.borrowBalanceCurrent(address(this));

            token.safeApprove(_cTokenAddress, _amt);

            // CHECK: IF USER HAS A BORROWBALANCE OF MORE THAN _repayAmount ON THIS TOKEN
            require(_amt <= cToken.borrowBalanceCurrent(address(this)), "REPAY AMOUNT MORE THAN BORROWED AMOUNT");

            // repay borrow
            require(cToken.repayBorrow(_amt) == 0, "REPAY FAILED");
        }
        setUint(setId, _amt);
        _eventName = "LogRepay(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _amt);
    }

    /**
     * @notice leverages tokens by depositing them, and borrowing against the deposit and finally depositing again
     * @notice makes use of deposit and borrow functions of the contract
     * @param _cTokenAddress address of the cToken contract in Compound
     * @param _tokenToLeverageAddress address to token/ETH to be leveraged 
     * @param _leverageAmount amount token/ETH (in Wei) to be leveraged
     * @param getId ID to retrieve amt.
     * @param setId ID stores the amount of tokens deposited.
    */
    function leverage(
        address payable _cTokenAddress,
        address _tokenToLeverageAddress,
        uint256 _leverageAmount,
        uint256 getId,
        uint256 setId
    ) payable external returns (string memory _eventName, bytes memory _eventParam) {  
        uint _amt = getUint(getId, _leverageAmount);
        if(_tokenToLeverageAddress == ethAddr){
            if(_amt == type(uint).max) _amt = address(this).balance;

            this.deposit{value: _amt}(ethAddr, _cTokenAddress, _amt, 0, 0);
            uint256 amountToBorrow = getMaxBorrowableAmount(_cTokenAddress, _amt);
            checkCollateral(_cTokenAddress, amountToBorrow);
            require(cEth.borrow(amountToBorrow) == 0, "BORROW FAILED");

            // deposit borrowed ETH again
            this.deposit{value: amountToBorrow}(ethAddr, _cTokenAddress, amountToBorrow, 0, 0);
        }
        else{
            IERC20 token = IERC20(_tokenToLeverageAddress);
            
            if(_amt == type(uint).max) _amt = token.balanceOf(address(this));

            deposit(_tokenToLeverageAddress, payable(_cTokenAddress), _amt, 0, 0);
            uint256 amountToBorrow = getMaxBorrowableAmount(_cTokenAddress, _amt);
            checkCollateral(_cTokenAddress, amountToBorrow);
            CErc20 cToken = CErc20(_cTokenAddress);

            // borrow
            require(cToken.borrow(amountToBorrow) == 0, "BORROW FAILED");

            // deposit borrowed erc20 to Compound again
            deposit(_tokenToLeverageAddress, _cTokenAddress, amountToBorrow, 0, 0);
        }
        setUint(setId, _amt);
        _eventName = "LogLeverage(address,address,uint256)";
        _eventParam = abi.encode(_tokenToLeverageAddress, _cTokenAddress, _amt);
    }

    /**
     *@dev fallback function to accept ether when borrowEth is called and send the eth back to owner
    */
    receive() external payable {}
}

contract ConnectV2Compound is CompoundMiddleContract {
    string constant public name = "Compound-v2"; 
}