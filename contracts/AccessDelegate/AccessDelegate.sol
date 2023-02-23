// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

import {OwnerVault} from "./OwnerVault.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "hardhat/console.sol";

contract AccessDelegate is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /// Minimum rental time
    uint256 public unitTime;
    uint256 public commission;
    uint256 public constant feeBase = 10000;
    address public adVault;

    EnumerableSet.AddressSet internal owners;
    /// @notice A mapping pointing owner address to its asset contract.
    mapping(address => address) public vaults;

    /// @notice rent status
    /// @dev RENTED can still be RENTABLE if the endTime is expired
    /// @dev UNRENTABLE means no more rental but can still be rented as the last rental may not expire.
    enum RentStatus {
        NONE,
        RENTABLE,
        RENTED,
        UNRENTABLE
    }

    struct TokenDetail {
        address contract_;
        uint256 tokenId;
        address depositor;
        address vault;
        address payment;
        uint256 unitFee;
        // The total number of times this token is rented
        uint256 totalCount;
        uint256 totalFee;
        uint256 totalAmount;
        uint256 lastRentIdx;
        uint256 endTime;
        RentStatus rentStatus;
    }

    struct Partner {
        address feeReceiver;
        uint256 commission;
        uint256 totalFee;
    }

    /// @notice All Partners' contracts
    EnumerableSet.AddressSet internal paymentContracts;
    /// @notice A mapping pointing partner's contract address to its total fee
    mapping(address => uint256) public payments;

    /// @notice All Partners' contracts
    EnumerableSet.AddressSet internal partnerContracts;
    /// @notice A mapping pointing partner's contract address to partner structs
    mapping(address => Partner) public partners;

    /// @notice An incrementing counter to create unique ids for each token
    uint256 public nextTokenIdx = 1;

    /// @notice A mapping pointing tokenId to TokenDetail structs
    mapping(uint256 => TokenDetail) public tokenDetails;

    /// @notice A mapping pointing token hash to tokenId
    mapping(bytes32 => uint256) public tokenIdxes;

    /// @notice All Tokens' contracts
    EnumerableSet.AddressSet internal tokenContracts;
    /// @notice A mapping pointing token's contract address to related token indexes
    mapping(address => EnumerableSet.UintSet) internal tokenIndexesByContract;

    struct Rental {
        address renter;
        address contract_;
        uint256 tokenId;
        address vault;
        uint256 endTime;
    }

    /// @notice An incrementing counter to create unique idx for each rental
    uint256 public totalRentCount = 0;

    /// @notice A mapping pointing rentIdx to the rental
    /// dev rentIdx -> rental
    mapping(uint256 => Rental) public rentals;

    /// @notice A double mappings pointing renter to contract to rentIdxes
    /// dev renter -> contract -> rentIdxes
    mapping(address => mapping(address => EnumerableSet.UintSet)) internal personalRentals;

    /// @notice Emitted on each token lent
    event TokenDelegated(address indexed depositer, address indexed contract_, uint256 tokenId, uint256 unitFee);

    /// @notice Emitted on each token rental
    event TokenRented(address indexed renter, uint256 tokenIdx, uint256 rentIdx, address indexed contract_, uint256 tokenId);

    /// @notice Emitted on each token lent cancel
    event TokenUndelegated(address indexed depositor, uint256 tokenIdx, address indexed contract_, uint256 tokenId);

    constructor(address adVault_, uint256 unitTime_, uint256 commission_) {
        // The commission cannot exceed 10%
        require(commission_ <= 1000, "commission too big");
        adVault = adVault_;
        unitTime = unitTime_;
        commission = commission_;
        paymentContracts.add(address(0));
    }

    /// @notice create a vault owned by msg.sender
    function createVault() external {
        require(vaults[msg.sender] == address(0), "You already have a vault");
        _createVault(msg.sender);
    }

    /// @notice delegate an NFToken to RentFun
    /// @param contract_ The NFToken contract that issue the tokens
    /// @param tokenId The id the NFToken
    /// @param unitFee The unit rental price
    function delegateNFToken(address contract_, uint256 tokenId, address payment, uint256 unitFee) external {
        require(paymentContracts.contains(payment), "Payment contract is not supported");

        if (vaults[msg.sender] == address(0)) {
            _createVault(msg.sender);
        }

        address vault = vaults[msg.sender];
        if (ERC721(contract_).ownerOf(tokenId) != vault) {
            ERC721(contract_).transferFrom(msg.sender, vault, tokenId);
        }

        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        uint256 tokenIdx = tokenIdxes[tokenHash];
        TokenDetail memory detail;
        if (tokenIdx == 0) {
            // The token is delegated for the first time
            tokenIdx = nextTokenIdx++;
            detail = TokenDetail(contract_, tokenId, msg.sender, vault, payment, unitFee, 0, 0, 0, 0, 0, RentStatus.RENTABLE);
            tokenIdxes[tokenHash] = tokenIdx;
        } else {
            // The token has ever been delegated, just update its detail
            detail = tokenDetails[tokenIdx];
            detail.depositor = msg.sender;
            detail.vault = vault;
            detail.payment = payment;
            detail.unitFee = unitFee;
            detail.rentStatus = RentStatus.RENTABLE;
        }
        tokenDetails[tokenIdx] = detail;
        tokenContracts.add(contract_);
        tokenIndexesByContract[contract_].add(tokenIdx);

        emit TokenDelegated(msg.sender, contract_, tokenId, unitFee);
    }

    /// @notice rent a token only if the token is available
    /// @param tokenIdx The only index for each NFToken
    /// @param amount The amount of unitTime and this rental's total time will be unitTime * amount
    function rentNFToken(uint256 tokenIdx, uint256 amount) external payable {
        TokenDetail memory detail = tokenDetails[tokenIdx];
        require(detail.rentStatus == RentStatus.RENTABLE ||
        (detail.rentStatus == RentStatus.RENTED && detail.endTime < block.timestamp), "Token is not rentable");
        require(amount > 0, "Rent period too short");
        require(detail.vault == ERC721(detail.contract_).ownerOf(detail.tokenId), "Token was not owned by its vault");
        uint256 totalFee = detail.unitFee.mul(amount);
        if (detail.payment == address(0)) require(msg.value == totalFee, "WRONG_FEE");

        uint256 platformFee = totalFee.mul(commission).div(feeBase);
        uint256 rentFee = totalFee.sub(platformFee);
        Partner memory ptn = partners[detail.contract_];
        uint256 partnerFee = platformFee.mul(ptn.commission).div(feeBase);
        platformFee = platformFee.sub(partnerFee);
        _pay(detail.payment, detail.depositor, rentFee);
        _pay(detail.payment, ptn.feeReceiver, partnerFee);
        _pay(detail.payment, adVault, platformFee);
        // update total fee
        ptn.totalFee = ptn.totalFee.add(partnerFee);
        partners[detail.contract_] = ptn;
        payments[detail.payment] = payments[detail.payment].add(totalFee);

        // update detail
        ++detail.totalCount;
        detail.totalFee = detail.totalFee.add(rentFee);
        detail.totalAmount = detail.totalAmount.add(amount);
        detail.lastRentIdx = ++totalRentCount;
        detail.endTime = block.timestamp.add(unitTime.mul(amount));
        detail.rentStatus = RentStatus.RENTED;
        tokenDetails[tokenIdx] = detail;

        // update rentals
        rentals[totalRentCount] = Rental(msg.sender, detail.contract_, detail.tokenId, detail.vault, detail.endTime);
        personalRentals[msg.sender][detail.contract_].add(totalRentCount);

        emit TokenRented(msg.sender, tokenIdx, detail.lastRentIdx, detail.contract_, detail.tokenId);
    }

    /// @notice undelegate an NFToken will just make it unrentable, the exist rents won't be affected.
    /// @param tokenIdx The idx of the NFToken
    function undelegateNFToken(uint256 tokenIdx) external {
        TokenDetail memory detail = tokenDetails[tokenIdx];
        require(msg.sender == detail.depositor, "Undelegate can only be done by the depositor");
        require(detail.rentStatus != RentStatus.UNRENTABLE, "Token is already UNRENTABLE");

        detail.rentStatus = RentStatus.UNRENTABLE;
        tokenDetails[tokenIdx] = detail;

        emit TokenUndelegated(msg.sender, tokenIdx, detail.contract_, detail.tokenId);
    }

    /// @notice check if a given token is rented or not
    function isNFTokenRented(address contract_, uint256 tokenId) public view returns (bool) {
        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        uint256 tokenIdx = tokenIdxes[tokenHash];
        if (tokenIdx == 0) return false;

        TokenDetail memory detail = tokenDetails[tokenIdx];
        /// @dev Undelegate A token that has never been rented will make it UNRENTABLE while
        /// detail.endTime is still 0
        return detail.rentStatus != RentStatus.UNRENTABLE || detail.endTime >= block.timestamp;
    }

    /// @notice check all rentals for a given renter.
    function getFullRentals(address renter, address contract_) external view returns (Rental[] memory fullRentals) {
        uint256[] memory rentIdxes = personalRentals[renter][contract_].values();
        if (rentIdxes.length == 0) return fullRentals;
        fullRentals = new Rental[](rentIdxes.length);
        for(uint i = 0; i < rentIdxes.length; i++) {
            fullRentals[i] = rentals[rentIdxes[i]];
        }
    }

    /// @notice check all alive rentals for a given renter.
    function getAliveRentals(address renter, address contract_) public view returns (Rental[] memory aliveRentals) {
        uint256[] memory rentIdxes = personalRentals[renter][contract_].values();
        uint256 count = 0;
        for(uint i = 0; i < rentIdxes.length; i++) {
            if (rentals[rentIdxes[i]].endTime >= block.timestamp) count++;
        }
        if (count == 0) return aliveRentals;
        aliveRentals = new Rental[](count);
        uint j = 0;
        for(uint i = 0; i < rentIdxes.length; i++) {
            if (rentals[rentIdxes[i]].endTime >= block.timestamp) aliveRentals[j++] = rentals[rentIdxes[i]];
        }
    }

    /// @notice get renting tokens by contract
    function getRentableTokens(address contract_) public view returns(TokenDetail[] memory details) {
        uint256[] memory tokenIndexes = tokenIndexesByContract[contract_].values();
        uint256 count = 0;
        TokenDetail memory detail;
        for(uint i = 0; i < tokenIndexes.length; i++) {
            detail = tokenDetails[tokenIndexes[i]];
            if (!isNFTokenRented(detail.contract_, detail.tokenId)) {
                count++;
            }
        }
        if (count == 0) return details;

        details = new TokenDetail[](count);
        uint j = 0;
        for(uint i = 0; i < tokenIndexes.length; i++) {
            detail = tokenDetails[tokenIndexes[i]];
            if (!isNFTokenRented(detail.contract_, detail.tokenId)) details[j++] = detail;
        }
    }

    /// @notice create a vault contract for each owner
    function _createVault(address owner) internal {
        OwnerVault ov = new OwnerVault(address(this));
        ov.transferOwnership(owner);
        vaults[owner] = address(ov);
    }

    /// @notice partners setter
    function setPartners(address contract_, address feeReceiver_, uint256 commission_) external onlyOwner {
        require(commission_ <= feeBase, "Partner commission too big");
        Partner storage ptn = partners[contract_];
        ptn.feeReceiver = feeReceiver_;
        ptn.commission = commission_;
        partners[contract_] = ptn;
        partnerContracts.add(contract_);
    }

    /// @notice UnitTime setter
    function setUnitTime(uint256 unitTime_) external onlyOwner {
        unitTime = unitTime_;
    }

    /// @notice Commission setter
    function setCommission(uint256 commission_) external onlyOwner {
        require(commission_ <= 1000, "Commission too big");
        commission = commission_;
    }

    /// @notice adVault setter
    function setAdVault(address adVault_) external onlyOwner {
        adVault = adVault_;
    }

    /// @notice owners getter
    function getOwners() public view returns (address[] memory) {
        return owners.values();
    }

    /// @notice partnerContracts getter
    function getPartnerContracts() public view returns (address[] memory) {
        return partnerContracts.values();
    }

    /// @notice tokenContracts getter
    function getTokenContracts() public view returns (address[] memory) {
        return tokenContracts.values();
    }

    /// @notice pay ether
    function _payEther(address payable recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool sent,) = recipient.call{value: amount}("");
        require(sent, "SEND_ETHER_FAILED");
    }

    /// @notice pay ether or ERC20
    function _pay(address payment, address recipient, uint256 amount) private {
        if (amount == 0) return;
        if (payment == address(0)) {
            _payEther(payable(recipient), amount);
        } else {
            ERC20(payment).safeTransfer(recipient, amount);
        }
    }

    /// @dev Helper function to compute hash for a given token
    function getTokenHash(address contract_, uint256 tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(contract_,  tokenId));
    }
}