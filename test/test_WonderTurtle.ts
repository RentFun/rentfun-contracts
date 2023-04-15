import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer, Contract, utils } from "ethers";
import {parseEther} from "ethers/lib/utils";
import { MerkleTree } from 'merkletreejs';

describe("WonderBird", () => {
    let alice: Signer;
    let bob: Signer;
    let carol: Signer;
    let dev: Signer;
    let aliceAddr: string;
    let bobAddr: string;
    let carolAddr: string;
    let devAddr: string;
    let WonderBird: Contract;
    let WonderBirdAddress: string;
    const AddressZero = ethers.constants.AddressZero;
    const baseURI = 'http://localhost:3000/'
    let merkleTree: MerkleTree;
    let aliceProof: string[];
    let bobProof: string[];
    let devProof: string[];
    const { keccak256 } = utils;
    const kevinAddr = '0x3353b44be83197747eB6a4b3B9d2e391c2A357d5';

    beforeEach(async () => {
        [alice, bob, carol, dev] = await ethers.getSigners();
        aliceAddr = await alice.getAddress();
        bobAddr = await bob.getAddress();
        carolAddr = await carol.getAddress();
        devAddr = await dev.getAddress();
        console.log("aliceAddr", aliceAddr);
        console.log("bobAddr", bobAddr);
        console.log("carolAddr", carolAddr);
        console.log("devAddr", devAddr);

        const whitelist = [aliceAddr, bobAddr, carolAddr];
        let leaves = whitelist.map((addr) => keccak256(addr));
        merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
        const merkleRootHash = merkleTree.getHexRoot();
        console.log('merkleRootHash', merkleRootHash);
        aliceProof = merkleTree.getHexProof(keccak256(aliceAddr));
        bobProof = merkleTree.getHexProof(keccak256(bobAddr));
        devProof = merkleTree.getHexProof(keccak256(devAddr));

        const WonderBirdFactory = await ethers.getContractFactory("WonderBird");
        WonderBird = await WonderBirdFactory.deploy(baseURI, merkleRootHash, aliceAddr);
        await WonderBird.deployed();
        WonderBirdAddress = WonderBird.address;
        console.log("WonderBird", WonderBirdAddress);
    });

    describe("contract function", () => {
        it("should be ok to get tokenURI", async () => {
            let ts = await WonderBird.totalSupply();
            expect(ts).equal(50);

            let tokenId = await WonderBird.tokenByIndex(0);
            const owner = await WonderBird.ownerOf(tokenId);
            expect(owner).to.equal(kevinAddr);

            const tokenURI = await WonderBird.tokenURI(tokenId);
            console.log("tokenURI", tokenURI);
        });

        it("mint fail and success", async () => {
            await expect(WonderBird.mint(951, [])).to.be.revertedWith(
                "Minting more tokens than available"
            );

            await expect(WonderBird.mint(1, [])).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderBird.mint(2, aliceProof)).to.be.revertedWith(
                "Exceeds mint limit"
            );

            await expect(WonderBird.mint(1, aliceProof, {value: parseEther("0.01")})).to.be.revertedWith(
                "Price mismatch"
            );

            let ts = await WonderBird.totalSupply();
            expect(ts).equal(50);

            const mintTx = await WonderBird.mint(1, aliceProof);
            expect(mintTx).to.be.ok;

            ts = await WonderBird.totalSupply();
            expect(ts).equal(51);

            let tokenId = await WonderBird.tokenByIndex(50);
            const owner = await WonderBird.ownerOf(tokenId);
            expect(owner).to.equal(aliceAddr);

            await expect(WonderBird.upgrade([tokenId], [])).to.be.revertedWith(
                "Length mismatch"
            );

            await expect(WonderBird.upgrade([tokenId], [0])).to.be.revertedWith(
                "Wrong neck trait value"
            );

            await expect(WonderBird.upgrade([tokenId], [6])).to.be.revertedWith(
                "Wrong neck trait value"
            );

            let tokenURI = await WonderBird.tokenURI(tokenId);
            console.log("UnrevealedTokenURI", tokenURI);
            expect(await WonderBird.reveal()).to.be.ok;
            tokenURI = await WonderBird.tokenURI(tokenId);
            console.log("RevealedTokenURI", tokenURI);
            expect(await WonderBird.upgrade([tokenId], [1])).to.be.ok;
            tokenURI = await WonderBird.tokenURI(tokenId);
            console.log("upgradedTokenURI", tokenURI);

            await expect(WonderBird.mint(1, devProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderBird.connect(dev).mint(1, devProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderBird.connect(bob).mint(1, aliceProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderBird.connect(dev).mint(1, bobProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );
        });

        //function UpdateStage(uint8 stage_, bytes32 merkleRootHash, uint256 price, uint256 limit) {

        it("mint fail and success after UpdateStage 2", async () => {
            const whitelist = [bobAddr, carolAddr, devAddr];
            let leaves = whitelist.map((addr) => keccak256(addr));
            merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
            const merkleRootHash = merkleTree.getHexRoot();
            console.log('merkleRootHash 2', merkleRootHash);
            aliceProof = merkleTree.getHexProof(keccak256(aliceAddr));
            bobProof = merkleTree.getHexProof(keccak256(bobAddr));

            const updateStageTx = await WonderBird.UpdateStage(merkleRootHash, parseEther("0.04"), 2);
            expect(updateStageTx).to.be.ok;

            await expect(WonderBird.mint(1, aliceProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderBird.connect(bob).mint(3, bobProof)).to.be.revertedWith(
                "Exceeds mint limit"
            );

            await expect(WonderBird.connect(bob).mint(2, bobProof, {value: parseEther("0.01")})).to.be.revertedWith(
                "Price mismatch"
            );

            const mintTx = WonderBird.connect(bob).mint(1, bobProof, {value: parseEther("0.04")});
            expect(mintTx).to.be.ok;
            await expect(WonderBird.connect(bob).mint(2, bobProof, {value: parseEther("0.04")})).to.be.revertedWith(
                "Exceeds mint limit"
            );
        });

        it("mint fail and success after UpdateStage 3", async () => {
            let stage = await WonderBird.stage();
            console.log("stage", stage);

            const updateStageTx = await WonderBird.UpdateStage(ethers.utils.formatBytes32String(""), parseEther("0.06"), 3);
            expect(updateStageTx).to.be.ok;

            await expect(WonderBird.mint(951, [])).to.be.revertedWith(
                "Minting more tokens than available"
            );

            await expect(WonderBird.mint(1, [])).to.be.revertedWith(
                "Price mismatch"
            );

            await expect(WonderBird.mint(2, [], {value: parseEther("0.06")})).to.be.revertedWith(
                "Price mismatch"
            );

            const mintTx = WonderBird.connect(bob).mint(2, bobProof, {value: parseEther("0.12")});
            expect(mintTx).to.be.ok;
            await expect(WonderBird.connect(bob).mint(2, [], {value: parseEther("0.12")})).to.be.revertedWith(
                "Exceeds mint limit"
            );
        });
    });
});

