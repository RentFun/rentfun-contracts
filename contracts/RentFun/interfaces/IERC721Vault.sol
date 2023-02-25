// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.4;

interface IERC721Vault {
    function transferNFT(address contract_, uint256 id, address to) external;
}
