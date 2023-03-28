import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

// const owners = ["0xBd39f5936969828eD9315220659cD11129071814", "0xBca9567A9e8D5F6F58C419d32aF6190F74C880e6"]
// const threshold = 2
// const AddressZero = "0x0000000000000000000000000000000000000000"
// const data = "0x"

const deploy_owner_vault: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment,
) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    await deploy("OwnerVault", {
        from: deployer,
        args: ['0xf7a84D01F4041D8719d27a8268Dc097b257C04FC'],
        log: true,
        deterministicDeployment: true,
    });
};

deploy_owner_vault.tags = ['OwnerVault']
export default deploy_owner_vault;
