import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "hardhat";

// const owners = ["0xBd39f5936969828eD9315220659cD11129071814", "0xBca9567A9e8D5F6F58C419d32aF6190F74C880e6"]
// const threshold = 2
// const AddressZero = "0x0000000000000000000000000000000000000000"
// const data = "0x"

const deploy_address_store: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment,
) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    await deploy("WonderBird", {
        from: deployer,
        args: ['ipfs://', ethers.utils.formatBytes32String(""), '0x3353b44be83197747eB6a4b3B9d2e391c2A357d5'],
        log: true,
        deterministicDeployment: true,
    });
};

deploy_address_store.tags = ['WonderBird']
export default deploy_address_store;
