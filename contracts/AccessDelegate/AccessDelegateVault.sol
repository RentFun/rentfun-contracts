pragma solidity ^0.8.4;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC721VaultInterface} from "./interfaces/ERC721VaultInterface.sol";

contract ERC721Vault is ERC721VaultInterface {
    address public AccessDelegate;

    constructor(address AccessDelegate_) {
        AccessDelegate = AccessDelegate_;
    }

    modifier onlyAccessDelegate() {
        require(msg.sender == AccessDelegate, "Invalid contract");
        _;
    }

    function transferTo(address contract_, uint256 id, address to) override external onlyAccessDelegate {
        ERC721(contract_).transferFrom(address(this), to, id);
    }
}

