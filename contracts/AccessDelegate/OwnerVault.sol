pragma solidity ^0.8.4;


import {AccessDelegate} from "./AccessDelegateV1.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";


import {ERC721VaultInterface} from "./interfaces/ERC721VaultInterface.sol";

contract ERC721Vault is Ownable, ERC721VaultInterface {
    address public accessDelegate;

    constructor(address accessDelegate_) {
        accessDelegate = accessDelegate_;
    }

    modifier ERC721NotRented(address contract_, uint256 tokenId) {
        AccessDelegate ad = AccessDelegate(accessDelegate);
        require(!ad.isNFTokenRented(contract_, tokenId), "Rented");
        _;
    }

    function transferERC721(address contract_, uint256 tokenId, address to)
        override external onlyOwner ERC721NotRented(contract_, tokenId) {
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

