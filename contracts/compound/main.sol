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
     * @param _amount number of tokens/ETH (in Wei) to deposit, uint(-1) for max. amount
    */
    function deposit(
        address _tokenAddress, 
        address payable _cTokenAddress, 
        uint256 _amount
    ) public payable returns (string memory _eventName, bytes memory _eventParam) {
        if(_tokenAddress == ethAddr){
            if(_amount == type(uint).max) _amount = msg.sender.balance;
            
            require(_amount == address(this).balance, "INCORRECT AMOUNT OF ETHER SENT");

            cEth.mint{value: _amount, gas: 250000}(); // no return, will revert on error
            console.log("Supplied %s wei to Compound via smart contract",_amount);
            console.log("Total ether deposits: ", cEth.balanceOfUnderlying(address(this)));
        }
        else{
            IERC20 token = IERC20(_tokenAddress);
            CErc20 cToken = CErc20(_cTokenAddress);

            if(_amount == type(uint).max) _amount = token.balanceOf(msg.sender);

            require(token.allowance(msg.sender, address(this)) >= _amount, "INSUFFICIENT ALLOWANCE");
            token.safeTransferFrom(owner, address(this), _amount);
            
            // Approve transfer on the ERC20 contract
            token.safeApprove(_cTokenAddress, _amount);

            // supply the tokens to Compound and mint cTokens
            require(cToken.mint(_amount) == 0, "TOKEN DEPOSIT FAILED");

            console.log("Total token deposits: ", cToken.balanceOfUnderlying(address(this)));
        }

        enterMarket(_cTokenAddress);

        _eventName = "LogDeposit(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _amount);
    }

    /**
     * @notice withdraws tokens deposited to compound by taking amount of cTokens to be redeemed as input
     * @dev uses redeem() function in Compound contract
     * @param _redeemAmount the number of cTokens to be redeemed
     * @param _cTokenAddress address of cToken contract on Compound
     * @param _tokenAddress address of ERC20 token to be withdrawn (ethAddr for ETH withdrawals)
    */
    function withdraw(
        uint256 _redeemAmount, 
        address _cTokenAddress, 
        address _tokenAddress
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        if(_tokenAddress == ethAddr) {
            if(_redeemAmount == type(uint).max){
                _redeemAmount = cEth.balanceOf(address(this));
            }
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
            if(_redeemAmount == type(uint).max){
                _redeemAmount = cToken.balanceOf(address(this));
            }

            require(cToken.balanceOf(address(this)) >= _redeemAmount, "INSUFFICIENT cTOKEN BALANCE");

            require(cToken.redeem(_redeemAmount) == 0, "ERROR WHILE REDEEMING");

            // transfer erc20 tokens back to user
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        _eventName = "LogWithdraw(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _redeemAmount);
    }

    /**
     * @notice borrows tokens/ETH from Compound using deposits as collateral
     * @dev uses all current deposits as collateral (to calculate liquidity), updates ethBorrowBalance after borrow
     * @param _tokenAddress address of token to borrow (ethAddr for ETH borrows)
     * @param _cTokenAddress address of cToken contract for the token being borrowed
     * @param _amountToBorrow amount to be borrowed
    */
    function borrow(
        address _tokenAddress,
        address _cTokenAddress,
        uint256 _amountToBorrow
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        checkCollateral(_cTokenAddress, _amountToBorrow);

        if(_tokenAddress == ethAddr) {

            require(cEth.borrow(_amountToBorrow) == 0, "BORROW FAILED");

            console.log("Borrowed %s wei", _amountToBorrow);

            (bool success, ) = owner.call{value: _amountToBorrow}("");
            require(success, "FAILURE IN SENDING ETHER TO USER");
            ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            IERC20 token = IERC20(_tokenAddress);
            
            // borrow
            require(cToken.borrow(_amountToBorrow) == 0, "BORROW FAILED");

            // transfer borrowed erc20 to user
            token.safeTransfer(owner, _amountToBorrow);
        }
        
        _eventName = "LogBorrow(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _amountToBorrow);
    }

    /**
     * @notice repays borrowed tokens
     * @dev updates ethBorrowBalance
     * @param _cTokenAddress address of the cToken contract in Compound
     * @param _tokenAddress address of token contract (ethAddr for ETH)
     * @param _repayAmount amount of token to be repayed
    */
    function repay(
        address _cTokenAddress, 
        address _tokenAddress,
        uint256 _repayAmount
    ) external payable returns (string memory _eventName, bytes memory _eventParam) {
        if(_tokenAddress == ethAddr) {
            
            if(_repayAmount == type(uint).max)_repayAmount = cEth.borrowBalanceCurrent(address(this)); 
        
            require(_repayAmount == msg.value, "INCORRECT AMOUNT OF ETHER SENT");
            // CHECK: IF msg.value ETH WAS EVEN BORROWED 
            ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
            require(_repayAmount <= ethBorrowBalance,"REPAY AMOUNT MORE THAN BORROWED AMOUNT");
            
            cEth.repayBorrow{value: msg.value, gas: 250000}();
            console.log("Repayed %s wei", msg.value);
            ethBorrowBalance = cEth.borrowBalanceCurrent(address(this));
        }
        else{
            CErc20 cToken = CErc20(_cTokenAddress);
            IERC20 token = IERC20(_tokenAddress);

            if(_repayAmount == type(uint).max)_repayAmount = cToken.borrowBalanceCurrent(address(this));

            // transfer user's tokens to contract
            token.safeTransferFrom(msg.sender, address(this), _repayAmount);

            // approve Compound to spend erc20 tokens
            token.safeApprove(_cTokenAddress, _repayAmount);

            // CHECK: IF USER HAS A BORROWBALANCE OF MORE THAN _repayAmount ON THIS TOKEN
            require(_repayAmount <= cToken.borrowBalanceCurrent(address(this)), "REPAY AMOUNT MORE THAN BORROWED AMOUNT");

            // repay borrow
            require(cToken.repayBorrow(_repayAmount) == 0, "REPAY FAILED");
        }

        _eventName = "LogRepay(address,address,uint256)";
        _eventParam = abi.encode(_tokenAddress, _cTokenAddress, _repayAmount);
    }

    /**
     * @notice leverages tokens by depositing them, and borrowing against the deposit and finally depositing again
     * @notice makes use of deposit and borrow functions of the contract
     * @param _cTokenAddress address of the cToken contract in Compound
     * @param _tokenToLeverageAddress address to token/ETH to be leveraged 
     * @param _leverageAmount amount token/ETH (in Wei) to be leveraged
    */
    function leverage(
        address payable _cTokenAddress,
        address _tokenToLeverageAddress,
        uint256 _leverageAmount
    ) payable external returns (string memory _eventName, bytes memory _eventParam) {
        if(_tokenToLeverageAddress == ethAddr){
            if(_leverageAmount == type(uint).max) _leverageAmount = msg.sender.balance;
            require(_leverageAmount == address(this).balance, "INCORRECT AMOUNT OF ETHER SENT");

            deposit(ethAddr, _cTokenAddress, msg.value);
            uint256 amountToBorrow = getMaxBorrowableAmount(_cTokenAddress, _leverageAmount);
            checkCollateral(_cTokenAddress, amountToBorrow);
            require(cEth.borrow(amountToBorrow) == 0, "BORROW FAILED");

            // deposit borrowed ETH again
            deposit(ethAddr, _cTokenAddress, amountToBorrow);
        }
        else{
            IERC20 token = IERC20(_tokenToLeverageAddress);
            
            if(_leverageAmount == type(uint).max) _leverageAmount = token.balanceOf(msg.sender);

            deposit(_tokenToLeverageAddress, payable(_cTokenAddress), _leverageAmount);
            uint256 amountToBorrow = getMaxBorrowableAmount(_cTokenAddress, _leverageAmount);
            checkCollateral(_cTokenAddress, amountToBorrow);
            CErc20 cToken = CErc20(_cTokenAddress);

            // borrow
            require(cToken.borrow(amountToBorrow) == 0, "BORROW FAILED");

            // deposit borrowed erc20 to Compound again
            deposit(_tokenToLeverageAddress, _cTokenAddress, amountToBorrow);
        }

        _eventName = "LogLeverage(address,address,uint256)";
        _eventParam = abi.encode(_tokenToLeverageAddress, _cTokenAddress, _leverageAmount);
    }

    /**
     *@dev fallback function to accept ether when borrowEth is called and send the eth back to owner
    */
    receive() external payable {}
}

contract ConnectV2Compound is CompoundMiddleContract {
    string constant public name = "Compound-v2"; 
}