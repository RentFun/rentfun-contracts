// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

import "./interfaces/IRentFun.sol";
import "./interfaces/IERC721Vault.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract OwnerVault is Ownable, IERC721Vault {
    address public rentFun;

    constructor(address rentFun_) {
        rentFun = rentFun_;
    }

    modifier NotRented(address contract_, uint256 tokenId) {
        require(!IRentFun(rentFun).isRented(contract_, tokenId), "RentFun: Token is rented");
        _;
    }

    function transferNFT(address contract_, uint256 id, address to)
        external override onlyOwner NotRented(contract_, id) {
        ERC721(contract_).transferFrom(address(this), to, id);
    }

//    function transferERC20() external onlyOwner onlyOperatorIsOwner {
//    }
//
//    function transferEther() external onlyOwner onlyOperatorIsOwner {
//    }
//
//    /// @notice Operator setter
//    function setOperator(address operator_) onlyRentFun {
//        operator = operator_;
//    }
}

