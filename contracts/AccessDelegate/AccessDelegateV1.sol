// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {ERC721VaultInterface} from "./interfaces/ERC721VaultInterface.sol";

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AccessDelegate is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public unitTime;
    uint256 public commission;
    uint256 public constant feeBase = 10000;
    uint256 public totalPlatFee = 0;
    address public vault;

    EnumerableSet.AddressSet public owners;
    /// @notice A mapping pointing owner address to its asset contract.
    mapping(address => address) public vaults;

    /// @notice rent status
    /// @dev RENTED can still be RENTABLE if the endTime is expired
    /// @dev UNRENTABLE means no more rental but can still be rented as the last rental may not expire.
    enum RentStatus {
        RENTABLE,
        RENTED,
        UNRENTABLE
    }

    struct TokenDetail {
        address contract_;
        uint256 tokenId;
        address depositor;
        address vault;
        uint256 unitFee;
        uint256 totalRentCount;
        uint256 totalFee;
        uint256 totalTime;
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
    EnumerableSet.AddressSet public contractSet;
    /// @notice A mapping pointing token's contract address to partner structs
    mapping(address => Partner) public partners;

    /// @notice An incrementing counter to create unique ids for each token
    uint256 public nextTokenIdx = 1;

    /// @notice A mapping pointing tokenId to TokenDetail structs
    mapping(uint256 => TokenDetail) public tokenDetails;

    /// @notice A mapping pointing token hash to tokenId
    mapping(byte32 => uint256) public tokenIdxes;

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
    mapping(address => mapping(address => uint256[])) internal rentalsByRenterAndContract;

    /// @notice Emitted on each token lent
    event TokenDelegated(address indexed depositer, address indexed contract_, uint256 tokenId, uint256 unitFee);

    /// @notice Emitted on each token rental
    event TokenRented(address indexed renter, uint256 tokenIdx, uint256 rentIdx, address indexed contract_, uint256 tokenId);

    /// @notice Emitted on each token lent cancel
    event TokenUndelegated(address indexed depositor, uint256 tokenIdx, address indexed contract_, uint256 tokenId);

    constructor(address feeReceiver_, uint256 unitTime_, uint256 commission_) {
        // The commission cannot exceed 10%
        require(commission_ <= 1000, "commission too big");
        feeReceiver = feeReceiver_;
        unitTime = unitTime_;
        commission = commission_;
    }

    /// @notice delegate an NFToken to RentFun
    /// @param contract_ The NFToken contract that issue the tokens
    /// @param tokenId The id the NFToken
    /// @param unitFee The unit rental price
    function delegateNFToken(address contract_, uint256 tokenId, uint256 unitFee) external {
        if (vaults[msg.sender] == address(0)) {
            _createVault(msg.sender);
        }

        address vault = vaults[msg.sender];
        if (ERC721(contract_).ownerOf(tokenId) != vault) {
            ERC721(contract_).transferFrom(msg.sender, vault, tokenId);
        }

        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        uint256 tokenIdx = tokenIdxes[tokenHash];
        if (tokenIdx == 0) {
            // The token is delegated for the first time
            tokenIdx = nextTokenIdx++;
            detail = TokenDetail(contract_, tokenId, msg.sender, vault, unitFee, 0, 0, 0, 0, 0, TokenStatus.RENTABLE);
            tokenIdxes[tokenHash] = tokenIdx;
        } else {
            // The token has ever been delegated, just update its detail
            detail = tokenDetails[idx];
            detail.depositor = msg.sender;
            detail.vault = vault;
            detail.unitFee = unitFee;
            detail.status = TokenStatus.RENTABLE;
        }
        tokenDetails[tokenIdx] = detail;

        emit TokenDelegated(msg.sender, contract_, tokenId, unitFee);
    }

    /// @notice rent a token only if the token is available
    /// @param tokenIdx The only index for each NFToken
    /// @param amount The amount of unitTime and this rental's total time will be unitTime * amount
    function rentNFToken(uint256 tokenIdx, uint256 amount) external payable {
        TokenDetail detail = tokenDetails[tokenIdx];
        require(detail.status == TokenStatus.RENTABLE || detail.endTime < block.timestamp, "Token is not rentable");
        require(amount > 0, "Rent period too short");
        require(detail.vault == ERC721(contract_).ownerOf(tokenId), "Token was transferred from the vault");

        if (detail.lastRentIdx != 0) {
            require(rentals[lastRentIdx].endTime < block.timestamp, "Token is being rented");
        }

        uint256 totalTime = unitTime.mul(amount);
        uint256 totalFee = unitFee.mul(amount);
        uint256 platformFee = totalFee.mul(commission).div(feeBase);
        uint256 rentFee = totalFee.sub(platformFee);
        _pay(detail.vault, rentFee, true);
        Partner ptn = partners[detail.contract_];
        if (ptn.commission != 0) {
            uint256 partnerFee = platformFee.mul(ptn.commission).div(feeBase);
            platformFee = platformFee.sub(partnerFee);
            _pay(ptn.feeReceiver, partnerFee, true);
            _pay(vault, platformFee, true);
            ptn.totalFee = ptn.totalFee.add(partnerFee);
            totalPlatFee = totalPlatFee.add(platformFee);
            partners[detail.contract_] = ptn;
        }

        // update detail
        detail.totalRentCount = detail.totalRentCount.add(1);
        detail.totalFee = detail.totalFee.add(totalFee);
        detail.totalTime = detail.totalTime.add(totalTime);
        detail.lastRentIdx = ++totalRentCount;
        detail.endTime = block.timestamp.add(totalTime);
        tokenDetails[tokenIdx] = detail;


        // update rentals
        rentals[detail.lastRentIdx] = Rental(msg.sender, detail.contract_, detail.tokenId, detail.vault, detail.endTime);
        uint256[] rentIdxes = rentalsByRenterAndContract[msg.sender][detail.contract_];
        rentIdxes.push(detail.lastRentIdx);
        rentalsByRenterAndContract[msg.sender][detail.contract_] = rentIdxes;

        emit TokenRented(msg.sender, tokenIdx, detail.lastRentIdx, detail.contract_, detail.tokenId);
    }

    /// @notice undelegate an NFToken will just make it unrentable, the exist rents won't be affected.
    /// @param tokenIdx The idx of the NFToken
    function undelegateNFToken(uint256 tokenIdx) external {
        TokenDetail detail = tokenDetails[tokenIdx];
        require(msg.sender == detail.depositor, "Undelegate can only be done by the depositor");
        require(detail.status != UNRENTABLE, "Token is already UNRENTABLE");

        detail.status = TokenStatus.UNRENTABLE;
        tokenDetails[tokenIdx] = detail;

        emit TokenUndelegated(msg.sender, tokenIdx, detail.contract_, detail.tokenId);
    }

    /// @notice check if a given token is rented or not
    function isNFTokenRented(address contract_, uint256 tokenId) external pure returns (bool) {
        bytes32 memory tokenHash = getTokenHash(contract_, tokenId);
        uint256 memory tokenIdx = tokenIdxes[tokenHash];
        if (tokenIdx == 0) return false;

        TokenDetail memory detail = tokenDetails[tokenIdx];
        /// @dev Undelegate A token that has never been rented will make it UNRENTABLE while
        /// detail.endTime is still 0
        return detail.rentStatus != RentStatus.RENTABLE && (detail.endTime == 0 || detail.endTime >= block.timestamp);
    }

    /// @notice check if a given address is renting a token for a given NFT contract.
    function getAliveRentals(address renter, address contract_) external pure returns (Rental[] memory) {
        uint256[] memory rentIdxes = rentalsByRenterAndContract[msg.sender][detail.contract_];
        uint256 rentalCount = 0;
        for(uint i = 0; i <= rentIdxes.length; i++) {
            Rental memory rental = Rentals[i];
            if (rental.endTime >= block.timestamp) rentalCount++;
        }

        Rental[rentalCount] memory aliveRentals = new Rental[](rentalCount);
        uint j = 0;
        for(uint i = 0; i <= rentIdxes.length; i++) {
            if (rental.endTime >= block.timestamp) aliveRentals[j++] = rentals[i];
        }

        return aliveRentals;

    }

    function _createVault(address owner) internal {
        OwnerVault vault = new OwnerVault(address(this));
        // todo Need to transfer ownership
        vaults[owner] = vault;
    }

    /// @notice contractSet setter
    function setPartners(address contract_, address feeReceiver_, uint256 commission_) onlyOwner {
        require(commission_ <= feeBase, "Partner commission too big");
        if (!contractSet.contains(contract_)) {
            contractSet.add(contract_);
        }

        Partner ptn = partners[contract_];
        ptn.feeReceiver = feeReceiver_;
        ptn.commission_ = ptn.commission_;
        partners[contract_] = ptn;
    }

    /// @notice UnitTime setter
    function setUnitTime(uint256 unitTime_) onlyOwner {
        unitTime = unitTime_;
    }

    /// @notice Commission setter
    function setCommission(uint256 commission_) onlyOwner {
        require(commission_ <= 1000, "Commission too big");
        commission = commission_;
    }

    /// @notice Vault setter
    function setVault(address vault_) onlyOwner {
        vault = vault_;
    }

    /// @dev Send ether
    function _pay(address payable recipient, uint256 amount, bool errorOnFail) internal {
        (bool sent,) = recipient.call{value: amount}("");
        require(sent || errorOnFail, "SEND_ETHER_FAILED");
    }

    /// @dev Helper function to compute hash for a given token
    function getTokenHash(address contract_, uint256 tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(contract_,  tokenId));
    }
}