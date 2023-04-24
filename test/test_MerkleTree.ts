import {MerkleTree} from "merkletreejs";
import { utils } from "ethers";

describe("MerkleTreeTree", () => {
    it("should generate MerkleHash", async function () {
        const whitelist = [
            '0xa7DeBb68F2684074Ec4354B68E36C34AF363Fd57',
            '0x38dF87028C451AD521B2FB1576732e9637A66e6f',
            '0xD2884241140347F16F21EAD8a766982363630670',
            '0x5dF922C896e9457A5CA59a568265dD8025B4D369',
            '0x3353b44be83197747eB6a4b3B9d2e391c2A357d5',
            '0x33a280189d3029a632d9f669775De2cDE666B590',
        ];

        const { keccak256 } = utils;
        let leaves = whitelist.map((addr) => keccak256(addr));
        let merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
        const merkleRootHash = merkleTree.getHexRoot();
        console.log('merkleRootHash', merkleRootHash);
    });

    it("should generate MerkleHash 1", async function () {
        const whitelist = [
            '0xa7DeBb68F2684074Ec4354B68E36C34AF363Fd57', '0x38dF87028C451AD521B2FB1576732e9637A66e6f',
            '0xD2884241140347F16F21EAD8a766982363630670', '0x5dF922C896e9457A5CA59a568265dD8025B4D369',
            '0xc69e55478fb4639C253e8310B3EeDCDfAE2E482A', '0x908DF508e7Cb714c32F1986bC29e9e350a70b1d6',
            '0x3353b44be83197747eB6a4b3B9d2e391c2A357d5', '0x33a280189d3029a632d9f669775De2cDE666B590',
            '0x918d9639FC79382D05E75f9Bc0CDF0ADfBFeC84a', '0xDc02343f2d08a9D97F999B2D7f53A10f6763F505',
            '0x8016a0D860e6b5fbD4E7D584bD5D26E2E9715E12', '0x4965D1C9f926622734Ad3c5C099361Fd1db60385',
            '0xd9Cd55b2CC8c4214E131794a89160ee7cf450A99', '0x92bbA661e597E61850b6502F6e40af3f449d1576'
        ];

        const { keccak256 } = utils;
        let leaves = whitelist.map((addr) => keccak256(addr));
        let merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
        const merkleRootHash = merkleTree.getHexRoot();
        console.log('merkleRootHash', merkleRootHash);
    });

    it("should generate MerkleHash 2", async function () {
        const whitelist = [
            '0xa7DeBb68F2684074Ec4354B68E36C34AF363Fd57','0xaD0bf51f7fc89e262edBbdF53C260088B024D857',
            '0x61ec251836671e2E3E3556f5CdED2F2847265373','0xc69e55478fb4639C253e8310B3EeDCDfAE2E482A',
            '0xED83d345811Bc94D69946CB034426A3203392ec5','0x563234864ee845F7147169fCB84F4B42F4277Adb',
            '0xF6Beb097a5DC796b86de16A46ca4E352EC359d0f','0x31996Afc0B4A2Dc72b14f0029A2A75A78e86344B',
            '0x5f38BB373dccB91AD9Fd3727C2b9BaF6DF9332D3','0xac0487E92a9602A9d57F6d431B559554589837f6',
            '0x02AEe0CE756fa0157294Ff3Ff48c1Dd02ADCCF04','0xC51feFB9eF83f2D300448b22Db6fac032F96DF3F',
            '0x7633Ae31E314067a261bAd184F7AEc9F997b14f5','0x65122E2F5b10640fA261F2f1ffC2536E4115e8f9',
            '0x92425Ec91237317d5D1ebbA94Cc6441dD8061F58','0x4D5e066A4685e9f29cEDe8F847FBC338F267360E',
            '0x908DF508e7Cb714c32F1986bC29e9e350a70b1d6','0xdf846E5d61Cb4b8C7bB5d237a0F88F269B34DEEd',
            '0x09020cf073eac09c9c6d63166a482d0a75137fd5','0xAc57df25f08e67122c2D191546FDf1e027C0127d',
            '0xfdC00627504AF3e315Db1579E69D3F7577Aee1d9','0xF3c0C25090ae1458FC152947Aab57253cB8E0F0F',
            '0x9e6c39f57E324fDA4D8397eE5a67E1A5c44a3f4e','0x269fFeC724c2e7521f904a3257b18a9d67A7e4f8',
            '0xdD20AB9a23E905726F342C059578437566369FC0','0x4cD575b1233c07674090A1C138ffca76DF7771b7',
            '0x69B62C4Fb201F7509BB0c3aCcc20F1291f801a46',
        ];

        const { keccak256 } = utils;
        let leaves = whitelist.map((addr) => keccak256(addr));
        let merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
        const merkleRootHash = merkleTree.getHexRoot();
        console.log('merkleRootHash', merkleRootHash);
    });
});