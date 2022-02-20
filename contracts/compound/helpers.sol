// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "./interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Helpers {

    address constant internal comptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address constant internal cEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address constant internal ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant internal uniswapAnchorViewAddress = 0x046728da7cb8272284238bD3e47909823d63A58D;

    Comptroller internal comptroller = Comptroller(comptrollerAddress);
    UniswapAnchoredView internal priceFeed = UniswapAnchoredView(uniswapAnchorViewAddress);
    CEth internal cEth = CEth(cEtherAddress);

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

        // liquidity is the USD value borrowable by the user, before it reaches liquidation (scaled up by 10**18)
        console.log("Liquidity available: ", liquidity);        

        // CHECK: IF USER IS ALLOWED TO BORROW THE AMOUNT ENTERED
        require(priceFeed.getUnderlyingPrice(_cTokenAddress) * _amountToBorrow <= liquidity * (10**18),
             "BORROW FAILED: NOT ENOUGH COLLATERAL");
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
            uint256 amountOfTokenDepositsInUsd = priceFeed.getUnderlyingPrice(markets[i]) * cToken.balanceOfUnderlying(address(this));
            totalCollateral = totalCollateral + amountOfTokenDepositsInUsd;
        }
        console.log(
            "Total Collateral in USD (scaled up by 10^36): ",
            totalCollateral
        );
        return totalCollateral; //  this value has actually been scaled by 1e36
    }

    /**
     *@dev returns the total value of all taken debt in USD (scaled up by 10**36)
    */
    function getTotalDebtInUsd() external returns (uint256) {
        address[] memory markets = comptroller.getAssetsIn(address(this));
        uint256 totalDebt = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            CErc20 cToken = CErc20(markets[i]);
            uint256 amountBorrowedInUsd = priceFeed.getUnderlyingPrice(markets[i]) * cToken.borrowBalanceCurrent(address(this));
            totalDebt = totalDebt + amountBorrowedInUsd;
        }
        console.log("Total Debt in USD (scaled up by 10^36): ", totalDebt);
        return totalDebt; //  this value has actually been scaled by 1e36
    }

    function getMaxBorrowableAmount(
        address _cTokenAddress, 
        uint256 _leverageAmount
    ) internal view returns (uint256) {
        (, uint collateralFactorMantissa, ) = comptroller.markets(_cTokenAddress);
        uint256 borrowableAmount = (collateralFactorMantissa - (1*(10**17))) * _leverageAmount / 10**18;
        return borrowableAmount;
    }
}