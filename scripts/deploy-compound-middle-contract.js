const hre = require("hardhat");

async function main() {

  // We get the contract to deploy
  const CompoundMiddleContract = await hre.ethers.getContractFactory("CompoundMiddleContract");
  const compoundMiddleContract = await CompoundMiddleContract.deploy();

  await compoundMiddleContract.deployed();

  console.log("CompoundMiddleContract deployed to:", compoundMiddleContract.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
