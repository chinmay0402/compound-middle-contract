// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./interface.sol";
import "./main.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Helpers } from "./helpers.sol";

contract Leverage is Helpers {
    using SafeERC20 for IERC20;

    /**
     * @dev leverages the supplied ether by supplying the amount, borrowing max. possible amount to the supply and supplying it again
     * @param _cEtherAddress address of cEther contract
     * @param _middleContractAddress address of middle contract (to be able to call borrow, deposit functions)
     */
    function leverageEther(
        address payable _cEtherAddress,
        address payable _middleContractAddress
    ) external payable returns (uint256 totalDebt, uint256 totalCollateral) {
        CompoundMiddleContract middle = CompoundMiddleContract(_middleContractAddress);
        uint256 supplyEth = msg.value;
        console.log(supplyEth);
        // supply ether
        middle.deposit{value: msg.value}(ethAddr, _cEtherAddress, msg.value);
        
        // calculate maximum borrowable amount for the supplied ether
        (, uint collateralFactorMantissa, ) = comptroller.markets(_cEtherAddress);
        uint256 borrowableEthAmount = (collateralFactorMantissa - (1*(10**17))) * supplyEth / 10**18;
        console.log("collateralFactorMantissa: ", (collateralFactorMantissa - (1*(10**17))));
        // borrow the amount
        middle.leverage(_cEtherAddress, ethAddr, borrowableEthAmount);

        totalCollateral = middle.getTotalCollateralInUsd();
        totalDebt = middle.getTotalDebtInUsd();
    }

    /**
     * @dev leverage ERC20 by supplying ERC20 tokens, borrowing the same tokens and depositing the borrowed amount again
     * @param _cTokenAddress address of cToken to leverage
     * @param _middleContractAddress address of middle contract
     * @param _erc20Address address of contract of token to be leveraged
     * @param _depositAmount number of tokens to supply initially
     */
    function leverageERC20(
        address _cTokenAddress,
        address payable _middleContractAddress,
        address _erc20Address,
        uint256 _depositAmount
    ) external returns (uint256 totalDebt, uint256 totalCollateral) {
        // IERC20 token = IERC20(_erc20Address);
        CompoundMiddleContract middle = CompoundMiddleContract(_middleContractAddress);

        // supply token
        middle.deposit(_erc20Address, payable(_cTokenAddress), _depositAmount);
        
        // calculate maximum borrowable amount for the supplied tokens
        (, uint collateralFactorMantissa, ) = comptroller.markets(_cTokenAddress);
        uint256 erc20BorrowAmount = (collateralFactorMantissa - 1*(10**17)) * _depositAmount / 10**18; 
        // borrow amount has been kept a little less than max. allowed to prevent immediate liquidity
        
        // borrow the amount and leverage
        middle.leverage(payable(_cTokenAddress), _erc20Address, erc20BorrowAmount);

        totalCollateral = middle.getTotalCollateralInUsd();
        totalDebt = middle.getTotalDebtInUsd();
    }

    /**
     *@dev fallback function to accept ether when borrowEth is called and send the eth back to owner
     */
    receive() external payable {}
}