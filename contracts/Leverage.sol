// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./interfaces/Compound.sol";
import "./CompoundMiddleContract.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Leverage {
    using SafeERC20 for IERC20;

    /**
     * @dev leverages the supplied ether by supplying the amount, borrowing max. possible amount to the supply and supplying it again
     * @param _cEtherAddress address of cEther contract
     * @param _comptrollerAddress address of Compound comptroller contract
     * @param _middleContractAddress address of middle contract (to be able to call borrow, deposit functions)
     */
    function leverageEther(
        address payable _cEtherAddress, 
        address _comptrollerAddress, 
        address payable _middleContractAddress
    ) external payable {
        CompoundMiddleContract middle = CompoundMiddleContract(_middleContractAddress);
        uint256 supplyEth = msg.value;
        console.log(supplyEth);
        // supply ether
        bool depositSuccess = middle.depositEth{value: msg.value}(_cEtherAddress);

        require(depositSuccess == true, "LEVERAGE: DEPOSIT FAILED");
        
        // calculate maximum borrowable amount for the supplied ether
        Comptroller comptroller = Comptroller(_comptrollerAddress);
        (, uint collateralFactorMantissa, ) = comptroller.markets(_cEtherAddress);
        uint256 borrowableEthAmount = (collateralFactorMantissa - (1*(10**17))) * supplyEth / 10**18;
        console.log("collateralFactorMantissa: ", (collateralFactorMantissa - (1*(10**17))));
        // borrow the amount
        middle.borrowEth(_cEtherAddress, _comptrollerAddress, _cEtherAddress, borrowableEthAmount, false, payable(address(this)));

        // deposit the borrowed ether again
        bool leverageSuccess = middle.depositEth{value: address(this).balance}(_cEtherAddress);

        require(leverageSuccess == true, "LEVERAGE: LEVERAGE SUPPLY FAILED");
    }


    // function leverageERC20(
    //     address _cTokenAddress, 
    //     address _comptrollerAddress, 
    //     address _middleContractAddress
    // ) external {

    // }

    /**
     *@dev fallback function to accept ether when borrowEth is called and send the eth back to owner
     */
    receive() external payable {}
}