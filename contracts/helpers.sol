// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./interfaces/Compound.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Helpers {

    address private comptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    Comptroller private comptroller = Comptroller(comptrollerAddress);

    function enterMarket(address _cTokenAddress) internal {
        address[] memory cTokens = new address[](1); // 1 is the array length
        // cTokens is the list of tokens for which the market is to be entered
        cTokens[0] = _cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets FAILED");
    }
}