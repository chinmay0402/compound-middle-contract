const { expect, should } = require("chai");
const { ethers } = require('hardhat');
const { parseEther, parseUnits } = require("ethers/lib/utils");
const cDaiAbi = require("./ABIs/cDaiAbi.js");

describe("Compound Middle Contract with ERC20 as DAI using ethers.getSigners()", function () {
    let middleContract, leverage;
    let owner;

    const cEtherAddress = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
    const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    const cDaiAddress = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643";
    const comptrollerAddress = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B";

    beforeEach(async () => {
        const middleContractFactory = await ethers.getContractFactory("CompoundMiddleContract");
        [owner] = await ethers.getSigners();
        middleContract = await middleContractFactory.deploy();
        // calling deploy() on a contractFactory will start contract deployment and return a Promise that resolves a contract
        // this object has a method for each of the smart contract functions
    });

    describe('Deployment', async () => {
        it('Should set the right owner', async () => {
            expect(await middleContract.getOwner()).to.eq(owner.address);
        })
    });

    describe('Deposit Ether', async () => {
        it('Should deposit ether in Compound', async () => {
            await expect(await middleContract.depositEth(cEtherAddress, {
                value: parseEther("1")
            })
            ).to.changeEtherBalances(
                [owner], [parseEther("-1")]
            )

            await expect(await middleContract.depositEth(cEtherAddress, {
                value: parseEther("2")
            })
            ).to.changeEtherBalances(
                [owner], [parseEther("-2")]
            )
        })
    })

    describe('Withdraw Ether', async () => {
        beforeEach(async () => {
            await expect(await middleContract.depositEth(cEtherAddress, {
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
        let Dai, cDai;
        beforeEach(async () => {
            // seed the user's address with some dai
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("0.000001", 18));
            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
        });

        it('Should fail when borrow is attempted without minting tokens', async () => {
            await expect(middleContract.borrowEth(cEtherAddress, comptrollerAddress, cDaiAddress, parseEther('0.0000000001')))
                .to.be.revertedWith("DEPOSIT TOKENS FIRST");
        })

        it('Should fail on attempting to borrow more than liquidity', async () => {
            await expect(() => middleContract.depositErc20(daiAddress, cDaiAddress, parseUnits("0.000001", 18)))
                .to.changeTokenBalance(Dai, cDai, parseUnits("0.000001", 18));

            // debug later for the BORROW FAILED (COMPTROLLER_REJECTED) thing
            await expect(middleContract.borrowEth(cEtherAddress, comptrollerAddress, cDaiAddress, parseEther('1000')))
                .to.be.revertedWith("BORROW FAILED: NOT ENOUGH COLLATERAL");
        });

        it('Should disburse loan amount', async () => {
            await expect(() => middleContract.depositErc20(daiAddress, cDaiAddress, parseUnits("0.000001", 18)))
                .to.changeTokenBalance(Dai, cDai, parseUnits("0.000001", 18));

            // call borrow
            // Note: Getting COMPTROLLER_REJECTED error with BORROW FAILED on increasing borrow amount even though liquidity was enough (debug later)
            await expect(await middleContract.borrowEth(cEtherAddress, comptrollerAddress, cDaiAddress, parseEther('0.0000000001')))
                .to.changeEtherBalances(
                    [owner], [parseEther('0.0000000001')]
                ); //  the ether balance of the user should increase after borrowed amount get transferred
        });
    });

    describe('Repay Ether', async () => {
        let Dai, cDai;
        beforeEach(async () => {
            // seed the user's address with some dai
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
            
            // deposit collateral
            await middleContract.depositErc20(daiAddress, cDaiAddress, parseUnits("1", 18));
            // console.log("Owner's balance: ", await ethers.provider.getBalance(owner.address));

            // borrow eth
            await middleContract.borrowEth(cEtherAddress, comptrollerAddress, cDaiAddress, parseEther('0.0001'));
            // console.log("Owner's balance: ", await ethers.provider.getBalance(owner.address));
        });

        it('Should fail on attempting to repay more than borrowed', async () => {
            await expect(middleContract.paybackEth(cEtherAddress, 250000, {
                value: parseEther('1000')
            })).to.be.revertedWith("REPAY AMOUNT MORE THAN BORROWED AMOUNT");
        })

        it('Should repay amount and update borrowBalanceCurrent', async () => {
            await middleContract.paybackEth(cEtherAddress, 250000, {
                value: parseEther('0.000100000001180074')
            });

            await expect(await middleContract.getEthBorrowBalance()).to.eq(0);
        })
    })

    describe('Deposit ERC20', async () => {
        let Dai, cDai;
        beforeEach(async () => {
            // seed the user's address with some dai
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("0.000001", 18));

            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
        });

        it('Should deposit ERC20 tokens to Compoud', async () => {
            await expect(() => middleContract.depositErc20(daiAddress, cDaiAddress, parseUnits('100', 0)))
                    .to.changeTokenBalances(Dai, [owner, cDai], [parseUnits('-100', 0), parseUnits('100', 0)]);
        })
    });

    describe('Withdraw ERC20', async () => {
        let Dai, cDai;
        beforeEach(async () => {
            // seed the user's address with some dai
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
            
            // deposit collateral
            await middleContract.depositErc20(daiAddress, cDaiAddress, parseUnits("1", 18));
        })

        it('Should fail on attempting to withdraw more than balance', async () => {
            await expect(middleContract.withdrawErc20(cDaiAddress, daiAddress, 2*4576928512))
                    .to.be.revertedWith("INSUFFICIENT BALANCE");
        });

        it('Should update token balances on withdraw', async () => {
            await expect(() => middleContract.withdrawErc20(cDaiAddress, daiAddress, 1000))
                    .to.changeTokenBalances(Dai, [owner, cDai], [parseUnits("218487144835", 0), parseUnits("-218487144835", 0)]); // increased amount to account for interest
        });
    });

    describe('Borrow ERC20 using ETH', async () => {
        let Dai, cDai;
        beforeEach(async () => {
            // seed the user's address with some dai
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
        });

        it('Should fail if borrow is attempted without depositing ETH', async () => {
            await expect(middleContract.borrowErc20(cEtherAddress, daiAddress, comptrollerAddress, cDaiAddress, parseUnits('100', 0)))
                    .to.be.revertedWith("DEPOSIT SAID TOKEN FIRST");
        });

        it('Should fail on trying to borrow more amount in tokens than liquidity', async () => {
            await middleContract.depositEth(cEtherAddress, {
                value: parseEther('0.01')
            })

            await expect(middleContract.borrowErc20(cEtherAddress, daiAddress, comptrollerAddress, cDaiAddress, parseUnits('1', 20)))
                    .to.be.revertedWith("BORROW FAILED: NOT ENOUGH COLLATERAL");
        });

        it('Should disburse loan tokens', async () => {
            await expect(() => middleContract.depositEth(cEtherAddress, {
                value: parseEther('1')
            })).to.changeEtherBalances(
                    [owner], [parseEther("-1")]
                )

            await expect(() => middleContract.borrowErc20(cEtherAddress, daiAddress, comptrollerAddress, cDaiAddress, parseUnits('100', 0)))
                .to.changeTokenBalances(Dai, [owner, cDai], [parseUnits('100', 0), parseUnits('-100', 0)]);
        });
    });

    describe('Repay ERC20', async () => {
        let Dai, cDai;
        beforeEach(async () => {
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("1", 18));
            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
            
            // deposit eth as collateral
            await middleContract.depositEth(cEtherAddress, {
                value: parseEther('1')
            });

            // borrow dai
            await middleContract.borrowErc20(cEtherAddress, daiAddress, comptrollerAddress, cDaiAddress, parseUnits('100', 0));
        });

        it('Should fail on trying to repay more than borrowed', async () => {
            await expect(middleContract.paybackErc20(cDaiAddress, daiAddress, parseUnits('110', 0)))
                    .to.be.revertedWith("REPAY AMOUNT MORE THAN BORROWED AMOUNT");
        });

        it('Should repay tokens and update borrowBalance', async () => {
            await expect(() => middleContract.paybackErc20(cDaiAddress, daiAddress, parseUnits('100', 0)))
            .to.changeTokenBalances(Dai, [owner, cDai], [parseUnits('-100', 0), parseUnits('100', 0)]);
        });
    });

    describe('Create Leveraged Ether Position', async () => {
        beforeEach(async () => {
            const leverageContractFactory = await ethers.getContractFactory("Leverage");
            leverage = await leverageContractFactory.deploy();
        })
        it('Should create a leveraged ETH position', async () => {
            await leverage.leverageEther(cEtherAddress, comptrollerAddress, middleContract.address, {
                value: parseEther('1')
            });
        })
    });

    describe('Create Leveraged ERC20 Position', async () => {
        let Dai, cDai;
        beforeEach(async () => {
            // seed the user's address with some dai
            const tokenArtifact = await artifacts.readArtifact("IERC20");
            Dai = new ethers.Contract(daiAddress, tokenArtifact.abi, ethers.provider);
            await Dai.connect(owner).approve(middleContract.address, parseUnits("2", 18));

            cDai = new ethers.Contract(cDaiAddress, cDaiAbi, ethers.provider);
            const leverageContractFactory = await ethers.getContractFactory("Leverage");
            leverage = await leverageContractFactory.deploy();
        });
        it('Should create a leveraged ERC20 position', async () => {
            await leverage.leverageERC20(cDaiAddress, comptrollerAddress, middleContract.address, daiAddress, parseUnits('1', 18));
        })
    });
});