import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  MultiSigWallet,
  NFT,
  NFTMarketplace
} from "../typechain-types";

describe("NFT Marketplace Contracts", function () {
  let multiSig: MultiSigWallet;
  let nft: NFT;
  let marketplace: NFTMarketplace;
  let owner1: SignerWithAddress;
  let owner2: SignerWithAddress;
  let owner3: SignerWithAddress;
  let buyer: SignerWithAddress;

  beforeEach(async function () {
    // Get test accounts
    [owner1, owner2, owner3, buyer] = await ethers.getSigners();

    // Deploy MultiSig
    const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet");
    multiSig = await MultiSigWallet.deploy([
      owner1.address,
      owner2.address,
      owner3.address
    ]) as MultiSigWallet;

    // Deploy NFT
    const NFT = await ethers.getContractFactory("NFT");
    nft = await upgrades.deployProxy(NFT, 
      [await multiSig.getAddress(), "OurkiveNFT", "ORKV"],
      { kind: "uups" }
    ) as NFT;
    await nft.waitForDeployment();

    // Deploy Marketplace
    const Marketplace = await ethers.getContractFactory("NFTMarketplace");
    marketplace = await upgrades.deployProxy(Marketplace,
      [await multiSig.getAddress()],
      { kind: "uups" }
    ) as NFTMarketplace;
    await marketplace.waitForDeployment();
  });

  describe("MultiSig", function () {
    it("Should correctly set up owners", async function() {
      expect(await multiSig.isOwner(owner1.address)).to.be.true;
      expect(await multiSig.isOwner(owner2.address)).to.be.true;
      expect(await multiSig.isOwner(owner3.address)).to.be.true;
    });
  });

  describe("NFT", function () {
    it("Should mint through MultiSig", async function() {
      // Create mint function data
      const mintData = nft.interface.encodeFunctionData("safeMint", [
        owner1.address, 
        "test-uri"
      ]);

      // Submit transaction
      await multiSig.connect(owner1).submitTransaction(
        await nft.getAddress(),
        0n,
        mintData
      );

      // Get confirmations
      await multiSig.connect(owner1).confirmTransaction(0);
      await multiSig.connect(owner2).confirmTransaction(0);

      // Execute mint
      await multiSig.connect(owner1).executeTransaction(0);

      // Verify mint
      expect(await nft.ownerOf(0)).to.equal(owner1.address);
      expect(await nft.tokenURI(0)).to.equal("test-uri");
    });
  });
});