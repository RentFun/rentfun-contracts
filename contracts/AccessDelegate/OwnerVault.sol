// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

import {AccessDelegate} from "./AccessDelegate.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {IERC721Vault} from "./interfaces/IERC721Vault.sol";

contract OwnerVault is Ownable, IERC721Vault {
    address public accessDelegate;

    constructor(address accessDelegate_) {
        accessDelegate = accessDelegate_;
    }

    modifier ERC721NotRented(address contract_, uint256 tokenId) {
        AccessDelegate ad = AccessDelegate(accessDelegate);
        require(!ad.isNFTokenRented(contract_, tokenId), "AccessDelegate: Token is rented");
        _;
    }

    function transferERC721(address contract_, uint256 id, address to)
        external override onlyOwner ERC721NotRented(contract_, id) {
        ERC721(contract_).transferFrom(address(this), to, id);
    }

//    function transferERC20() external onlyOwner onlyOperatorIsOwner {
//    }
//
//    function transferEther() external onlyOwner onlyOperatorIsOwner {
//    }
//
//    /// @notice Operator setter
//    function setOperator(address operator_) onlyAccessDelegate {
//        operator = operator_;
//    }
}

