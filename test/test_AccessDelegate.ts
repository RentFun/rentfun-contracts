import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer, Contract, ContractFactory } from "ethers";
import {parseEther} from "ethers/lib/utils";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("AccessDelegate", () => {
    let NFToken: Contract;
    let alice: Signer;
    let bob: Signer;
    let carol: Signer;
    let dev: Signer;
    let aliceAddr: string;
    let bobAddr: string;
    let carolAddr: string;
    let devAddr: string;
    let AccessDelegate: Contract;
    let NFTokenAddress: string;
    let AccessDelegateAddress: string;
    const Hour = 60 * 60;
    let OwnerVaultFactory: ContractFactory;
    const AddressZero = ethers.constants.AddressZero;

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
        const NFTokenFactory = await ethers.getContractFactory("NFToken");

        NFToken = await NFTokenFactory.deploy();
        await NFToken.deployed();
        NFTokenAddress = NFToken.address;
        console.log("NFToken", NFTokenAddress);
        const AccessDelegateFactory = await ethers.getContractFactory("AccessDelegate");

        AccessDelegate = await AccessDelegateFactory.deploy(aliceAddr, Hour, 1000);
        await AccessDelegate.deployed();
        AccessDelegateAddress = AccessDelegate.address;
        console.log("AccessDelegate", AccessDelegateAddress);

        OwnerVaultFactory = await ethers.getContractFactory("OwnerVault");

        expect(await AccessDelegate.setPartners(NFTokenAddress, aliceAddr, 5000)).to.be.ok;
        expect(await AccessDelegate.setUnitTime(Hour)).to.be.ok;
        expect(await AccessDelegate.setCommission(1000)).to.be.ok;
        expect(await AccessDelegate.setAdVault(devAddr)).to.be.ok;
    });

    // function delegateNFToken(address contract_, uint256 tokenId, uint256 unitFee) external {

    describe("delegateNFToken", () => {
        it("should reverted with the tokenID is not minted", async () => {
            await expect(AccessDelegate.delegateNFToken(NFTokenAddress, 1, AddressZero, 1000)).to.be.revertedWith(
                "ERC721: invalid token ID"
            );
        });

        it("should reverted with the msg.sender is not the owner of the token", async () => {
            await NFToken.mintCollectionNFT(aliceAddr, 1);
            await NFToken.mintCollectionNFT(bobAddr, 2);
            await expect(AccessDelegate.delegateNFToken(NFTokenAddress, 2, AddressZero, 1000)).to.be.revertedWith(
                "ERC721: caller is not token owner or approved"
            );

            await expect(AccessDelegate.connect(bob).delegateNFToken(NFTokenAddress, 1, AddressZero, 1000)).to.be.revertedWith(
                "ERC721: caller is not token owner or approved"
            );

            // revert without approve
            await expect(AccessDelegate.delegateNFToken(NFTokenAddress, 1, AddressZero, 1000)).to.be.revertedWith(
                "ERC721: caller is not token owner or approved"
            );
        });

        it("should be ok to delegate an NFToken after approved", async () => {
            await NFToken.mintCollectionNFT(aliceAddr, 1);
            await NFToken.mintCollectionNFT(bobAddr, 2);

            let nextTokenIdx = await AccessDelegate.nextTokenIdx();
            expect(nextTokenIdx).to.equal(1);

            expect(await NFToken.approve(AccessDelegateAddress, 1)).to.be.ok;
            expect(await AccessDelegate.delegateNFToken(NFTokenAddress, 1, AddressZero, 1000)).to.be.ok;
            const aliceVaultAddr = await AccessDelegate.vaults(aliceAddr);
            console.log("aliceVaultAddr", aliceVaultAddr);
            let tokenOwner = await NFToken.ownerOf(1);
            expect(tokenOwner).to.equal(aliceVaultAddr);
            nextTokenIdx = await AccessDelegate.nextTokenIdx();
            expect(nextTokenIdx).to.equal(2);

            const td1 = await AccessDelegate.tokenDetails(1);
            expect(td1.contract_).to.equal(NFTokenAddress);
            expect(td1.depositor).to.equal(aliceAddr);
            expect(td1.unitFee).to.equal(1000);
            expect(td1.rentStatus).to.equal(1);

            expect(await NFToken.connect(bob).approve(AccessDelegateAddress, 2)).to.be.ok;
            expect(await AccessDelegate.connect(bob).delegateNFToken(NFTokenAddress, 2, AddressZero, 3000)).to.be.ok;

            const bobVaultAddr = await AccessDelegate.vaults(bobAddr);
            console.log("bobVaultAddr", bobVaultAddr);
            tokenOwner = await NFToken.ownerOf(2);
            expect(tokenOwner).to.equal(bobVaultAddr);
            nextTokenIdx = await AccessDelegate.nextTokenIdx();
            expect(nextTokenIdx).to.equal(3);

            const td2 = await AccessDelegate.tokenDetails(2);
            expect(td2.contract_).to.equal(NFTokenAddress);
            expect(td2.depositor).to.equal(bobAddr);
            expect(td2.unitFee).to.equal(3000);
            expect(td2.rentStatus).to.equal(1);
        });

        it("should reverted with token is rented while trying transferERC721", async () => {
            await NFToken.mintCollectionNFT(aliceAddr, 1);
            expect(await NFToken.approve(AccessDelegateAddress, 1)).to.be.ok;
            expect(await AccessDelegate.delegateNFToken(NFTokenAddress, 1, AddressZero, parseEther("1"))).to.be.ok;
            let tokenOwner = await NFToken.ownerOf(1);
            const aliceVaultAddr = await AccessDelegate.vaults(aliceAddr);
            expect(tokenOwner).to.equal(aliceVaultAddr);
            let isRented = await AccessDelegate.isNFTokenRented(NFTokenAddress, 1);
            expect(isRented).to.be.true;
            const OwnerVault = OwnerVaultFactory.attach(aliceVaultAddr);
            await expect(OwnerVault.connect(alice).transferERC721(NFTokenAddress, 1, aliceAddr)).to.be.revertedWith(
                "AccessDelegate: Token is rented"
            );

            expect(await AccessDelegate.undelegateNFToken(1)).to.be.ok;
            expect(await OwnerVault.connect(alice).transferERC721(NFTokenAddress, 1, aliceAddr)).to.be.ok;
            tokenOwner = await NFToken.ownerOf(1);
            expect(tokenOwner).to.equal(aliceAddr);

            // transferERC721 will fail if the token is rented
            expect(await NFToken.approve(AccessDelegateAddress, 1)).to.be.ok;
            expect(await AccessDelegate.delegateNFToken(NFTokenAddress, 1, AddressZero, parseEther("1"))).to.be.ok;
            const rentTx = await AccessDelegate.connect(carol).rentNFToken(1, 3, {value: parseEther("3")});
            expect(rentTx).to.be.ok;
            isRented = await AccessDelegate.isNFTokenRented(NFTokenAddress, 1);
            expect(isRented).to.be.true;
            expect(await AccessDelegate.undelegateNFToken(1)).to.be.ok;
            isRented = await AccessDelegate.isNFTokenRented(NFTokenAddress, 1);
            expect(isRented).to.be.true;
            await time.increase(3600*3);
            isRented = await AccessDelegate.isNFTokenRented(NFTokenAddress, 1);
            expect(isRented).to.be.false;
            expect(await OwnerVault.connect(alice).transferERC721(NFTokenAddress, 1, aliceAddr)).to.be.ok;
        });
    })

    describe("rentNFToken", () => {
        it("should reverted with token is not rentable", async () => {
            await expect(AccessDelegate.connect(carol).rentNFToken(1, 3)).to.be.revertedWith(
                "Token is not rentable"
            );
        });

        it("should be ok to rent an delegated NFToken", async () => {
            // alice delegate a token
            await NFToken.mintCollectionNFT(aliceAddr, 1);
            expect(await NFToken.approve(AccessDelegateAddress, 1)).to.be.ok;
            expect(await AccessDelegate.delegateNFToken(NFTokenAddress, 1, AddressZero, parseEther("1"))).to.be.ok;

            // no rent before
            let totalRentCount = await AccessDelegate.totalRentCount();
            expect(totalRentCount).to.be.equal(0);
            let carolFullRentals = await AccessDelegate.getFullRentals(carolAddr, NFTokenAddress);
            expect(carolFullRentals.length).to.equal(0);
            let carolAliveRentals = await AccessDelegate.getAliveRentals(carolAddr, NFTokenAddress);
            expect(carolAliveRentals.length).to.equal(0);


            const carolBalanceBeforeRent = await carol.getBalance();
            // after a rent
            const rentTx = await AccessDelegate.connect(carol).rentNFToken(1, 3, {value: parseEther("3")});
            expect(rentTx).to.be.ok;

            totalRentCount = await AccessDelegate.totalRentCount();
            expect(totalRentCount).to.be.equal(1);
            const td1 = await AccessDelegate.tokenDetails(1);
            expect(td1.totalCount).to.be.equal(1);
            expect(td1.totalFee).to.be.equal(parseEther("2.7"));
            expect(td1.totalAmount).to.be.equal(3);
            expect(td1.lastRentIdx).to.be.equal(totalRentCount);
            expect(td1.rentStatus).to.equal(2);

            const ptn = await AccessDelegate.partners(NFTokenAddress);
            expect(ptn.feeReceiver).to.equal(aliceAddr);
            expect(ptn.commission).to.equal(5000);
            expect(ptn.totalFee).to.equal(parseEther("0.15"));

            const aliceVaultAddr = await AccessDelegate.vaults(aliceAddr);
            const rental = await AccessDelegate.rentals(totalRentCount);
            expect(rental.renter).to.equal(carolAddr);
            expect(rental.contract_).to.equal(NFTokenAddress);
            expect(rental.tokenId).to.equal(1);
            expect(rental.vault).to.equal(aliceVaultAddr);

            carolFullRentals = await AccessDelegate.getFullRentals(carolAddr, NFTokenAddress);
            carolAliveRentals = await AccessDelegate.getAliveRentals(carolAddr, NFTokenAddress);
            expect(rental.toString()).to.equal(carolFullRentals[0].toString());
            expect(rental.toString()).to.equal(carolAliveRentals[0].toString());

            const carolBalanceAfterRent = await carol.getBalance();
            const before = carolBalanceBeforeRent.div(parseEther("1"));
            const after = carolBalanceAfterRent.div(parseEther("1"));
            expect(before.sub(after)).to.equal(3);
        });
    });
})