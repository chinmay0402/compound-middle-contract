const { expect, should } = require("chai");
const { ethers } = require('hardhat');
const { parseEther, parseUnits } = require("ethers/lib/utils");
const cBATAbi = require("./ABIs/cBATAbi.js");

describe("Compound Middle Contract using impersonate_account with ERC20 token as BAT", function () {
    let middleContract, leverage;
    let owner;

    const ethAddr = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const cEtherAddress = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
    const BATAddress = "0x0D8775F648430679A709E98d2b0Cb6250d2887EF";
    const cBATAddress = "0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E";

    beforeEach(async () => {
        const middleContractFactory = await ethers.getContractFactory("CompoundMiddleContract");
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: ["0x9d3937226a367bedcE0916F9Cee4490D22214c7C"],
        });
        owner = await ethers.getSigner("0x9d3937226a367bedcE0916F9Cee4490D22214c7C")
        middleContract = await middleContractFactory.connect(owner).deploy();
        // calling deploy() on a contractFactory will start contract deployment and return a Promise that resolves a contract
        // this object has a method for each of the smart contract functions
    });

    describe('Deployment', async () => {
        it('Should set the right owner', async () => {
            expect(await middleContract.getOwner()).to.eq(owner.address);
            // console.log(owner.address);
        })
    });

    describe('Deposit Ether', async () => {
        it('Should deposit ether in Compound', async () => {
            await expect(await middleContract.deposit(ethAddr, cEtherAddress, parseEther('1'), {
                value: parseEther("1")
            })
            ).to.changeEtherBalances(
                [owner], [parseEther("-1")]
            )

            await expect(await middleContract.deposit(ethAddr, cEtherAddress, parseEther('2'), {
                value: parseEther("2")
            })
            ).to.changeEtherBalances(
                [owner], [parseEther("-2")]
            )
        })
    })

    describe('Withdraw Ether', async () => {
        beforeEach(async () => {
            await expect(await middleContract.deposit(ethAddr, cEtherAddress, parseEther('3'), {
                value: parseEther("3")
            }));
        })
        describe('Success', async () => {
            it('Should withdraw ether from Compound and send it to user', async () => {
                await expect(await middleContract.withdrawEth(
                    4985102208,
                    cEtherAddress
                )).to.changeEtherBalances(
                    // parseEther is >1 to take interest into account
                    [owner], [parseEther('1.000000001668029933')] // change to something better later
                )
            })
        });

        describe('Failure', async () => {
            it('Should reject withdraws greater than balance', async () => {
                await expect(middleContract.withdrawEth(
                    19940408832,
                    cEtherAddress
                )).to.be.revertedWith("NOT ENOUGH cTOKENS");
            })
        });

    })

    describe('Borrow Ether', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            // seed the user's address with some BAT
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("0.000001", 18));
            // console.log(await BAT.balanceOf(owner.address));
            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
        });

        it('Should fail on attempting to borrow more than liquidity', async () => {
            await expect(() => middleContract.deposit(BATAddress, cBATAddress, parseUnits("0.000001", 18)))
                .to.changeTokenBalance(BAT, cBAT, parseUnits("0.000001", 18));

            // debug later for the BORROW FAILED (COMPTROLLER_REJECTED) thing
            await expect(middleContract.borrowEth(parseEther('1000')))
                .to.be.revertedWith("BORROW FAILED: NOT ENOUGH COLLATERAL");
        });

        it('Should disburse loan amount', async () => {
            await expect(() => middleContract.deposit(BATAddress, cBATAddress, parseUnits("0.000001", 18)))
                .to.changeTokenBalance(BAT, cBAT, parseUnits("0.000001", 18));

            // call borrow
            // Note: Getting COMPTROLLER_REJECTED error with BORROW FAILED on increasing borrow amount even though liquidity was enough (debug later)
            await expect(await middleContract.borrowEth(parseEther('0.0000000001')))
                .to.changeEtherBalances(
                    [owner], [parseEther('0.0000000001')]
                ); //  the ether balance of the user should increase after borrowed amount get transferred
        });
    });

    describe('Repay Ether', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            // seed the user's address with some BAT
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
            
            // deposit collateral
            await middleContract.deposit(BATAddress, cBATAddress, parseUnits("0.01", 18));
            // console.log("Owner's balance: ", await ethers.provider.getBalance(owner.address));

            // borrow eth
            await middleContract.borrowEth(parseEther('0.000001'));
            // console.log("Owner's balance: ", await ethers.provider.getBalance(owner.address));
        });

        it('Should fail on attempting to repay more than borrowed', async () => {
            await expect(middleContract.paybackEth(cEtherAddress, 250000, {
                value: parseEther('1000')
            })).to.be.revertedWith("REPAY AMOUNT MORE THAN BORROWED AMOUNT");
        })

        it('Should repay amount and update borrowBalanceCurrent', async () => {
            await middleContract.paybackEth(cEtherAddress, 250000, {
                value: parseEther('0.000001000000011800')
            });

            await expect(await middleContract.getEthBorrowBalance()).to.eq(0);
        })
    })

    describe('Deposit ERC20', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            // seed the user's address with some BAT
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("100", 18));

            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
        });

        it('Should deposit ERC20 tokens to Compound', async () => {
            await expect(() => middleContract.deposit(BATAddress, cBATAddress, parseUnits('100', 18)))
                    .to.changeTokenBalances(BAT, [owner, cBAT], [parseUnits('-100', 18), parseUnits('100', 18)]);
        })
    });

    describe('Withdraw ERC20', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            // seed the user's address with some BAT
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
            
            // deposit collateral
            await middleContract.deposit(BATAddress, cBATAddress, parseUnits("1", 18));
        })

        it('Should fail on attempting to withdraw more than balance', async () => {
            await expect(middleContract.withdrawErc20(cBATAddress, BATAddress, 2*4576928512))
                    .to.be.revertedWith("INSUFFICIENT BALANCE");
        });

        it('Should update token balances on withdraw', async () => {
            await expect(() => middleContract.withdrawErc20(cBATAddress, BATAddress, 1000))
                    .to.changeTokenBalances(BAT, [owner, cBAT], [parseUnits("206623687121", 0), parseUnits("-206623687121", 0)]); // increased amount to account for interest
        });
    });

    describe('Borrow ERC20 using ETH', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            // seed the user's address with some BAT
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
        });

        it('Should fail on trying to borrow more amount in tokens than liquidity', async () => {
            await middleContract.deposit(ethAddr, cEtherAddress, parseEther('0.01'), {
                value: parseEther('0.01')
            })

            await expect(middleContract.borrowErc20(BATAddress, cBATAddress, parseUnits('1', 20)))
                    .to.be.revertedWith("BORROW FAILED: NOT ENOUGH COLLATERAL");
        });

        it('Should disburse loan tokens', async () => {
            await expect(() => middleContract.deposit(ethAddr, cEtherAddress, parseEther('1'), {
                value: parseEther('1')
            })).to.changeEtherBalances(
                    [owner], [parseEther("-1")]
                )

            await expect(() => middleContract.borrowErc20(BATAddress, cBATAddress, parseUnits('100', 0)))
                .to.changeTokenBalances(BAT, [owner, cBAT], [parseUnits('100', 0), parseUnits('-100', 0)]);
        });
    });

    describe('Repay ERC20', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
            
            // deposit eth as collateral
            await middleContract.deposit(ethAddr, cEtherAddress, parseEther('1'), {
                value: parseEther('1')
            });

            // borrow BAT
            await middleContract.borrowErc20(BATAddress, cBATAddress, parseUnits('100', 0));
        });

        it('Should fail on trying to repay more than borrowed', async () => {
            await expect(middleContract.paybackErc20(cBATAddress, BATAddress, parseUnits('110', 0)))
                    .to.be.revertedWith("REPAY AMOUNT MORE THAN BORROWED AMOUNT");
        });

        it('Should repay tokens and update borrowBalance', async () => {
            await expect(() => middleContract.paybackErc20(cBATAddress, BATAddress, parseUnits('100', 0)))
            .to.changeTokenBalances(BAT, [owner, cBAT], [parseUnits('-100', 0), parseUnits('100', 0)]);
        });
    });

    describe('Create Leveraged Ether Position', async () => {
        beforeEach(async () => {
            const leverageContractFactory = await ethers.getContractFactory("Leverage");
            leverage = await leverageContractFactory.deploy();
        })
        it('Should create a leveraged ETH position', async () => {
            await leverage.leverageEther(cEtherAddress, middleContract.address, {
                value: parseEther('1')
            });
        })
    });

    describe('Create Leveraged ERC20 Position', async () => {
        let BAT, cBAT;
        beforeEach(async () => {
            // seed the user's address with some BAT
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            BAT = new ethers.Contract(BATAddress, tokenArtifact.abi, ethers.provider);
            await BAT.connect(owner).approve(middleContract.address, parseUnits("2", 18));

            cBAT = new ethers.Contract(cBATAddress, cBATAbi, ethers.provider);
            const leverageContractFactory = await ethers.getContractFactory("Leverage");
            leverage = await leverageContractFactory.deploy();
        });
        it('Should create a leveraged ERC20 position', async () => {
            await leverage.leverageERC20(cBATAddress, middleContract.address, BATAddress, parseUnits('1', 18));
        })
    });
});