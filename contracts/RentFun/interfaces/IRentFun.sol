// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.4;

interface IRentFun {
    struct Rental {
        address renter;
        address contract_;
        uint256 tokenId;
        address vault;
        uint256 endTime;
    }

    function lend(address contract_, uint256 tokenId, address payment, uint256 unitFee) external;
    function rent(address contract_, uint256 tokenId, uint256 amount) external payable;
    function cancelLend(address contract_, uint256 tokenId) external;


    function isRented(address contract_, uint256 tokenId) external view returns (bool);
    function getAliveRentals(address renter, address contract_) external view returns (Rental[] memory aliveRentals);
}