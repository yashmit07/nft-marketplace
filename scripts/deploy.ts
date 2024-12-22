import { ethers, upgrades } from "hardhat";

async function main() {
  // Get the first three test accounts
  const [owner1, owner2, owner3] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", owner1.address);
  console.log("MultiSig Owners:");
  console.log("Owner 1:", owner1.address);
  console.log("Owner 2:", owner2.address);
  console.log("Owner 3:", owner3.address);

  // 1. Deploy MultiSig first since it's non-upgradeable and needed as admin
  console.log("\nDeploying MultiSigWallet...");
  const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet");
  const multiSig = await MultiSigWallet.deploy([
    owner1.address,
    owner2.address,
    owner3.address
  ]);
  await multiSig.waitForDeployment();
  console.log("MultiSigWallet deployed to:", await multiSig.getAddress());

  // 2. Deploy NFT contract with MultiSig as admin
  console.log("\nDeploying NFT contract...");
  const NFT = await ethers.getContractFactory("NFT");
  const nft = await upgrades.deployProxy(NFT, 
    [await multiSig.getAddress(), "OurkiveNFT", "ORKV"],
    { kind: "uups" }
  );
  await nft.waitForDeployment();
  console.log("NFT contract deployed to:", await nft.getAddress());

  // 3. Deploy Marketplace with MultiSig as admin
  console.log("\nDeploying Marketplace...");
  const Marketplace = await ethers.getContractFactory("NFTMarketplace");
  const marketplace = await upgrades.deployProxy(Marketplace,
    [await multiSig.getAddress()],
    { kind: "uups" }
  );
  await marketplace.waitForDeployment();
  console.log("Marketplace deployed to:", await marketplace.getAddress());

  // Log all addresses for easy reference
  console.log("\nDeployment Summary:");
  console.log("--------------------");
  console.log("MultiSigWallet:", await multiSig.getAddress());
  console.log("NFT:", await nft.getAddress());
  console.log("Marketplace:", await marketplace.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });