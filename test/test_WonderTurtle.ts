import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer, Contract, utils } from "ethers";
import {parseEther} from "ethers/lib/utils";
import { MerkleTree } from 'merkletreejs';

describe("WonderTurtle", () => {
    let alice: Signer;
    let bob: Signer;
    let carol: Signer;
    let dev: Signer;
    let aliceAddr: string;
    let bobAddr: string;
    let carolAddr: string;
    let devAddr: string;
    let WonderTurtle: Contract;
    let WonderTurtleAddress: string;
    const AddressZero = ethers.constants.AddressZero;
    const baseURI = 'http://localhost:3000/'
    let merkleTree: MerkleTree;
    let aliceProof: string[];
    let bobProof: string[];
    let devProof: string[];
    const { keccak256 } = utils;

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

        const WonderTurtleFactory = await ethers.getContractFactory("WonderTurtle");
        WonderTurtle = await WonderTurtleFactory.deploy(baseURI, merkleRootHash, aliceAddr, aliceAddr);
        await WonderTurtle.deployed();
        WonderTurtleAddress = WonderTurtle.address;
        console.log("WonderTurtle", WonderTurtleAddress);
    });

    describe("contract function", () => {
        it("should be ok to get tokenURI", async () => {
            const owner = await WonderTurtle.ownerOf(1);
            expect(owner).to.equal(aliceAddr);

            const tokenURI = await WonderTurtle.tokenURI(1);
            console.log("tokenURI", tokenURI);
        });

        it("mint fail and success", async () => {
            await expect(WonderTurtle.mint(951, [])).to.be.revertedWith(
                "Exceeds max supply"
            );

            await expect(WonderTurtle.mint(1, [])).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderTurtle.mint(2, aliceProof)).to.be.revertedWith(
                "Exceeds mint limit"
            );

            await expect(WonderTurtle.mint(1, aliceProof, {value: parseEther("0.01")})).to.be.revertedWith(
                "Price mismatch"
            );

            let ts = await WonderTurtle.totalSupply();
            expect(ts).equal(50);

            const mintTx = await WonderTurtle.mint(1, aliceProof);
            expect(mintTx).to.be.ok;

            ts = await WonderTurtle.totalSupply();
            expect(ts).equal(51);

            const tokenURI = await WonderTurtle.tokenURI(ts);
            expect(tokenURI).equal('http://localhost:3000/51.token.json');

            await expect(WonderTurtle.mint(1, devProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderTurtle.connect(dev).mint(1, devProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderTurtle.connect(bob).mint(1, aliceProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderTurtle.connect(dev).mint(1, bobProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );
        });

        //function UpdateStage(uint8 stage_, bytes32 merkleRootHash, uint256 price, uint256 limit) {

        it("mint fail and success after UpdateStage to 2", async () => {
            const whitelist = [bobAddr, carolAddr, devAddr];
            let leaves = whitelist.map((addr) => keccak256(addr));
            merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
            const merkleRootHash = merkleTree.getHexRoot();
            console.log('merkleRootHash 2', merkleRootHash);
            aliceProof = merkleTree.getHexProof(keccak256(aliceAddr));
            bobProof = merkleTree.getHexProof(keccak256(bobAddr));

            const updateStageTx = await WonderTurtle.UpdateStage(2, merkleRootHash, parseEther("0.04"), 2);
            expect(updateStageTx).to.be.ok;

            await expect(WonderTurtle.mint(1, aliceProof)).to.be.revertedWith(
                "Minter is not in the whitelist"
            );

            await expect(WonderTurtle.connect(bob).mint(3, bobProof)).to.be.revertedWith(
                "Exceeds mint limit"
            );

            await expect(WonderTurtle.connect(bob).mint(2, bobProof, {value: parseEther("0.01")})).to.be.revertedWith(
                "Price mismatch"
            );

            const mintTx = WonderTurtle.connect(bob).mint(1, bobProof, {value: parseEther("0.04")});
            expect(mintTx).to.be.ok;
            await expect(WonderTurtle.connect(bob).mint(2, bobProof, {value: parseEther("0.04")})).to.be.revertedWith(
                "Exceeds mint limit"
            );
        });

        it("mint fail and success after UpdateStage to 3", async () => {
            const updateStageTx = await WonderTurtle.UpdateStage(3, ethers.utils.formatBytes32String(""), parseEther("0.06"), 3);
            expect(updateStageTx).to.be.ok;

            await expect(WonderTurtle.mint(951, [])).to.be.revertedWith(
                "Exceeds max supply"
            );

            await expect(WonderTurtle.mint(1, [])).to.be.revertedWith(
                "Price mismatch"
            );

            await expect(WonderTurtle.mint(2, [], {value: parseEther("0.06")})).to.be.revertedWith(
                "Price mismatch"
            );

            const mintTx = WonderTurtle.connect(bob).mint(2, bobProof, {value: parseEther("0.12")});
            expect(mintTx).to.be.ok;
            await expect(WonderTurtle.connect(bob).mint(2, [], {value: parseEther("0.12")})).to.be.revertedWith(
                "Exceeds mint limit"
            );
        });
    });
});

