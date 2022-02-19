// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./interfaces/Compound.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Helpers {

    address constant internal comptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address constant internal cEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address constant internal ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    Comptroller internal comptroller = Comptroller(comptrollerAddress);
    CEth cEth = CEth(cEtherAddress);

    function enterMarket(address _cTokenAddress) internal {
        address[] memory cTokens = new address[](1); // 1 is the array length
        // cTokens is the list of tokens for which the market is to be entered
        cTokens[0] = _cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets FAILED");
    }

    function checkCollateral(address _cTokenAddress, uint256 _amountToBorrow) internal view {

        (uint256 error1, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        require(error1 == 0, "comptroller.getAccountLiquidity FAILED");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        // liquidity is the USD value borrowable by the user, before it reaches liquidation
        console.log("Liquidity available: ", liquidity);        

        // CHECK: IF USER IS ALLOWED TO BORROW THE AMOUNT ENTERED
        require(UniswapAnchoredView(0x046728da7cb8272284238bD3e47909823d63A58D)
                .getUnderlyingPrice(_cTokenAddress) * _amountToBorrow <= liquidity * (10**18),
             "BORROW FAILED: NOT ENOUGH COLLATERAL");
    }
}