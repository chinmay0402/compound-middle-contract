// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./interfaces/Compound.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CompoundMiddleContract {
    using SafeERC20 for IERC20;

    address private owner; // required to send the received eth back to the user

    constructor() {
        owner = msg.sender; // sets contract owner
    }

    function getOwner() view external returns (address) {
        return owner;
    }

    /**
     * @dev deposits Ether to Compound protocol
            uses the mint() method in CEth contract
     * @param _cEtherAddress address of the cEth contract of Compound
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
     * @param _redeemAmount the number of cTokens to be redeemed
     * @param _cEtherAddress address of cEth contract on Compound
     * @return bool status of transaction
     */
    function withdrawEth(
        uint256 _redeemAmount,
        address _cEtherAddress
    ) external returns (bool) {
        CEth cEth = CEth(_cEtherAddress);

        uint256 redeemResult;

        require(
            cEth.balanceOf(address(this)) >= _redeemAmount,
            "NOT ENOUGH cTOKENS"
        );

        redeemResult = cEth.redeem(_redeemAmount);
        require(redeemResult == 0, "ERROR WHILE REDEEMING");
        
        uint256 amountOfEthreceived = _redeemAmount * cEth.exchangeRateCurrent();

        console.log(
            "Redeemed %s cEth for %s ether",
            _redeemAmount,
            amountOfEthreceived
        );

        (bool success, ) = owner.call{ value: address(this).balance }("");
        require(success, "FAILURE, ETHER NOT SENT");

        return true;
    }

    /**
     * @dev borrows Eth from Compound keeping another token as collateral
     * @param _cEtherAddress address of the cEther contract in Compound
     * @param _comptrollerAddress address of the comptroller contract in Compound
     * @param _cTokenAddress address of the cToken contract in Compound
     * @param _erc20Address address of contract of the token to be supplied as collateral
     * @param _erc20TokenToSupplyAsCollateral amount of tokens to supply as collateral
     * @param _amountToBorrowInWei amount of ether to be borrowed in wei
     * @return uint256 the current borrow balance of the user
     */
    function borrowEth(
        address payable _cEtherAddress,
        address _comptrollerAddress,
        address _cTokenAddress,
        address _erc20Address,
        uint256 _erc20TokenToSupplyAsCollateral,
        uint256 _amountToBorrowInWei
    ) public returns (uint256) {
        // declare references to external contracts
        CEth cEth = CEth(_cEtherAddress);
        Comptroller comptroller = Comptroller(_comptrollerAddress);
        CErc20 cToken = CErc20(_cTokenAddress);

        require(cToken.balanceOf(address(this)) > 0, "DEPOSIT TOKENS FIRST");

        // enter the market with the cTokens received (to make the above supplied tokens collateral)
        address[] memory cTokens = new address[](1); // 1 is the array length
        // cTokens is the list of tokens for which the market is to be entered
        cTokens[0] = _cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets FAILED");

        console.log(
            "Placed %s tokens (%s) as collateral",
            _erc20TokenToSupplyAsCollateral,
            _erc20Address
        );

        (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        require(error2 == 0, "comptroller.getAccountLiquidity FAILED");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        console.log("Liquidity available", liquidity); // liquidity is the USD value borrowable by the user, before it reaches liquidation

        // borrow
        require(cEth.borrow(_amountToBorrowInWei) == 0, "BORROW FAILED");
        uint256 borrowBalance = cEth.borrowBalanceCurrent(address(this));

        console.log("Borrowed %s eth", _amountToBorrowInWei / 18);

        (bool success, ) = owner.call{ value: address(this).balance }("");

        require(success, "FAILURE, ETHER NOT SENT");

        return borrowBalance;
    }

    /**
     * @dev repays borrowed eth
     * @param _cEtherAddress address of the cEth contract in Compound
     * @return uint256 updated borrow balance of the user
     */
    function paybackEth(
        address _cEtherAddress,
        uint256 gas
    ) public payable returns (uint256) {
        CEth cEth = CEth(_cEtherAddress);
        cEth.repayBorrow{value: msg.value, gas: gas}();

        console.log("Repayed %s ether", msg.value);

        return cEth.borrowBalanceCurrent(address(this));
    }

    /**
     * @dev deposits erc20 tokens to Compound, mints cTokens
     * @param _erc20Contract address of the erc20 token contract
     * @param _cErc20Contract address of the Compound contract for cTokens
     * @param _numTokensToSupply number of erc20 tokens to deposit
     * @return uint256 0 on successful transaction, otherwise error code
     */
    function depositErc20(
        address _erc20Contract,
        address _cErc20Contract,
        uint256 _numTokensToSupply
    ) external returns (uint256) {
        // create references to the contracts on mainnet
        IERC20 token = IERC20(_erc20Contract);
        CErc20 cToken = CErc20(_cErc20Contract);

        token.safeTransferFrom(msg.sender, address(this), _numTokensToSupply);

        // Approve transfer on the ERC20 contract
        token.safeApprove(_cErc20Contract, _numTokensToSupply);

        // supply the tokens to Compound and mint cTokens
        uint256 mintResult = cToken.mint(_numTokensToSupply);

        return mintResult;
    }

    /**
     * @dev withdraws erc20 tokens from Compound
     * @param _cErc20Contract address of the cErc20 contract on Compound
     * @param _erc20Contract address of the erc20 token
     * @param _amount can be number of cTokens or amount of erc20 tokens depending upon _redeemType
     * @return bool status of transaction
     */
    function withdrawErc20(
        address _cErc20Contract, 
        address _erc20Contract, 
        uint256 _amount
    ) external returns (bool) {
        // Create a reference to the cToken contract
        CErc20 cToken = CErc20(_cErc20Contract);
        IERC20 token = IERC20(_erc20Contract);

        uint256 redeemResult;

        // Retrieve asset based on cToken amount
        redeemResult = cToken.redeem(_amount);

        require(redeemResult == 0, "ERROR WHILE REDEEMING");

        token.safeTransfer(msg.sender, _amount);

        return true;
    }

    /**
     * @dev borrows erc20 token with ether as collateral
     * @param _cEtherAddress address of cEther contract in Compound
     * @param _erc20Address address of erc20 token contract
     * @param _comptrollerAddress address of comptroller contract in Compound
     * @param _amountToBorrow amount of erc20 tokens to borrow
     * @return uint256 borrowBalance of the user
     */
    function borrowErc20WithEth(
        address payable _cEtherAddress,
        address _erc20Address,
        address _comptrollerAddress,
        address _cTokenAddress,
        uint256 _amountToBorrow
    ) external payable returns (uint256) {
        // Create references to Compound and Token contracts
        CEth cEth = CEth(_cEtherAddress);
        CErc20 cToken = CErc20(_cTokenAddress);
        IERC20 token = IERC20(_erc20Address);
        Comptroller comptroller = Comptroller(_comptrollerAddress);

        // Deposit Eth as collateral
        require(cEth.balanceOf(address(this)) > 0, "DEPOSIT ETHER FIRST");

        // enter market with Eth
        address[] memory cTokens = new address[](1);
        cTokens[0] = _cEtherAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets FAILED");

        (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        require(error2 == 0, "comptroller.getAccountLiquidity FAILED");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        console.log("Liquidity available: ", liquidity);

        // borrow
        uint256 borrowStatus = cToken.borrow(_amountToBorrow);
        require(borrowStatus == 0, "BORROW FAILED");

        // get borrow balance
        uint256 borrowBalance = cToken.borrowBalanceCurrent(address(this));

        // transfer borrowed erc20 to user
        token.safeTransfer(owner, _amountToBorrow);

        return borrowBalance;
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
        token.safeApprove(_cErc20Address, _repayAmount);

        // repay borrow
        cToken.repayBorrow(_repayAmount);

        return cToken.borrowBalanceCurrent(address(this));
    }

    /**
     *@dev fallback function to accept ether when borrowEth is called and send the eth back to owner
     */
    receive() external payable {}
}
