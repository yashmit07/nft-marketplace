import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("NFT Marketplace Integration", function () {
  let multiSig: Contract;
  let nft: Contract;
  let marketplace: Contract;
  let owner1: SignerWithAddress;
  let owner2: SignerWithAddress;
  let owner3: SignerWithAddress;
  let seller: SignerWithAddress;
  let buyer: SignerWithAddress;

  beforeEach(async function () {
    // Get test accounts
    [owner1, owner2, owner3, seller, buyer] = await ethers.getSigners();

    // Deploy all contracts
    const MultiSigWallet = await ethers.getContractFactory("MultiSigWallet");
    multiSig = await MultiSigWallet.deploy([owner1.address, owner2.address, owner3.address]);
    await multiSig.waitForDeployment();

    const NFT = await ethers.getContractFactory("NFT");
    nft = await upgrades.deployProxy(NFT, 
      [await multiSig.getAddress(), "OurkiveNFT", "ORKV"],
      { kind: "uups" }
    );
    await nft.waitForDeployment();

    const Marketplace = await ethers.getContractFactory("NFTMarketplace");
    marketplace = await upgrades.deployProxy(Marketplace,
      [await multiSig.getAddress()],
      { kind: "uups" }
    );
    await marketplace.waitForDeployment();

    // Mint NFT to seller through MultiSig
    const mintInterface = new ethers.Interface([
      "function safeMint(address to, string memory uri)"
    ]);
    const mintData = mintInterface.encodeFunctionData("safeMint", [seller.address, "testURI"]);

    await multiSig.connect(owner1).submitTransaction(await nft.getAddress(), 0, mintData);
    await multiSig.connect(owner1).confirmTransaction(0);
    await multiSig.connect(owner2).confirmTransaction(0);
    await multiSig.connect(owner1).executeTransaction(0);
  });

  describe("Full Marketplace Flow", function () {
    const PRICE = ethers.parseEther("1"); // 1 ETH

    it("Should complete full listing and purchase cycle", async function () {
      // 1. Approve marketplace to handle NFT
      await nft.connect(seller).approve(await marketplace.getAddress(), 0);

      // 2. List NFT
      await marketplace.connect(seller).listItem(
        await nft.getAddress(),
        0,
        PRICE
      );

      // 3. Verify listing
      const listing = await marketplace.getListing(await nft.getAddress(), 0);
      expect(listing.price).to.equal(PRICE);
      expect(listing.seller).to.equal(seller.address);

      // 4. Buy NFT
      await marketplace.connect(buyer).buyItem(
        await nft.getAddress(),
        0,
        { value: PRICE }
      );

      // 5. Verify ownership transfer
      expect(await nft.ownerOf(0)).to.equal(buyer.address);

      // 6. Verify seller can withdraw proceeds
      const initialBalance = await ethers.provider.getBalance(seller.address);
      await marketplace.connect(seller).withdrawProceeds();
      const finalBalance = await ethers.provider.getBalance(seller.address);
      expect(finalBalance > initialBalance).to.be.true;
    });

    it("Should handle listing updates", async function () {
      // 1. First approve and list
      await nft.connect(seller).approve(await marketplace.getAddress(), 0);
      await marketplace.connect(seller).listItem(
        await nft.getAddress(),
        0,
        PRICE
      );

      // 2. Update price
      const NEW_PRICE = ethers.parseEther("2");
      await marketplace.connect(seller).updateListing(
        await nft.getAddress(),
        0,
        NEW_PRICE
      );

      // 3. Verify new price
      const listing = await marketplace.getListing(await nft.getAddress(), 0);
      expect(listing.price).to.equal(NEW_PRICE);
    });

    it("Should handle listing cancellation", async function () {
      // 1. First approve and list
      await nft.connect(seller).approve(await marketplace.getAddress(), 0);
      await marketplace.connect(seller).listItem(
        await nft.getAddress(),
        0,
        PRICE
      );

      // 2. Cancel listing
      await marketplace.connect(seller).cancelListing(
        await nft.getAddress(),
        0
      );

      // 3. Verify listing is removed
      const listing = await marketplace.getListing(await nft.getAddress(), 0);
      expect(listing.price).to.equal(0);
    });
  });
});