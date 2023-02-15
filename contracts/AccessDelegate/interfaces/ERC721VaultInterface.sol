pragma solidity 0.8.4;

interface ERC721VaultInterface {
    function transferTo(address contract_, uint256 id, address to) external;
}
