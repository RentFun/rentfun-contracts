// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

import "./Enum.sol";
import "./OwnerVault.sol";
import "./interfaces/IRentFun.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract RentFun is Ownable, IRentFun {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /// Minimum rental time
    uint256 public unitTime;
    uint256 public commission;
    uint256 public constant feeBase = 10000;
    address public beneficiary;

    EnumerableSet.AddressSet internal owners;
    /// @notice A mapping pointing owner address to its asset contract.
    mapping(address => address) public vaults;

    struct TokenDetail {
        address contract_;
        uint256 tokenId;
        address depositor;
        address vault;
        address payment;
        uint256 unitFee;
        uint256 lastRentIdx;
        uint256 endTime;
        Enum.RentStatus rentStatus;
    }

    struct Partner {
        address feeReceiver;
        uint256 commission;
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

    /// @notice An incrementing counter to create unique idx for each rental
    uint256 public totalRentCount = 0;

    /// @notice A mapping pointing rentIdx to the rental
    /// dev rentIdx -> rental
    mapping(uint256 => Rental) public rentals;

    /// @notice A double mappings pointing renter to contract to rentIdxes
    /// dev renter -> contract -> rentIdxes
    mapping(address => mapping(address => EnumerableSet.UintSet)) internal personalRentals;

    /// @notice Emitted on each token lent
    event TokenLent(address indexed depositer, address indexed contract_, uint256 tokenId, uint256 unitFee);

    /// @notice Emitted on each token rental
    event TokenRented(address indexed renter, uint256 rentIdx, address indexed contract_, uint256 tokenId);

    /// @notice Emitted on each token lent cancel
    event LentCanceled(address indexed depositor, address indexed contract_, uint256 tokenId);

    constructor(address contractOwner, address beneficiary_, uint256 unitTime_, uint256 commission_) {
        beneficiary = beneficiary_;
        unitTime = unitTime_;
        commission = commission_;
        paymentContracts.add(address(0));
        _transferOwnership(contractOwner);
    }

    /// @notice create a vault owned by msg.sender
    function createVault() external {
        require(vaults[msg.sender] == address(0), "You already have a vault");
        _createVault(msg.sender);
    }

    /// @notice lend an NFToken
    /// @param contract_ The NFToken contract that issue the tokens
    /// @param tokenId The id the NFToken
    /// @param payment The contract of payment way
    /// @param unitFee The unit rental price
    function lend(address contract_, uint256 tokenId, address payment, uint256 unitFee) external override {
        require(paymentContracts.contains(payment), "Payment contract is not supported");

        if (vaults[msg.sender] == address(0)) {
            _createVault(msg.sender);
        }

        address vault = vaults[msg.sender];
        if (ERC721(contract_).ownerOf(tokenId) != vault) {
            ERC721(contract_).transferFrom(msg.sender, vault, tokenId);
        }

        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        if (tokenIdxes[tokenHash] == 0) tokenIdxes[tokenHash] = nextTokenIdx++;
        tokenDetails[tokenIdxes[tokenHash]] = TokenDetail(contract_, tokenId, msg.sender, vault, payment, unitFee,
            tokenDetails[tokenIdxes[tokenHash]].lastRentIdx,
            tokenDetails[tokenIdxes[tokenHash]].endTime, Enum.RentStatus.RENTABLE);

        emit TokenLent(msg.sender, contract_, tokenId, unitFee);
    }

    /// @notice rent a token only if the token is available
    /// @param contract_ The NFToken contract that issue the tokens
    /// @param tokenId The id the NFToken
    /// @param amount The amount of unitTime and this rental's total time will be unitTime * amount
    function rent(address contract_, uint256 tokenId, uint256 amount) external payable override {
        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        uint256 tokenIdx = tokenIdxes[tokenHash];
        TokenDetail memory detail = tokenDetails[tokenIdx];
        require(detail.rentStatus == Enum.RentStatus.RENTABLE ||
        (detail.rentStatus == Enum.RentStatus.RENTED && detail.endTime < block.timestamp), "Token is not rentable");
        require(amount > 0, "Rent period too short");
        require(detail.vault == ERC721(contract_).ownerOf(tokenId), "Token was not owned by its vault");
        uint256 totalFee = detail.unitFee.mul(amount);
        if (detail.payment == address(0)) require(msg.value == totalFee, "WRONG_FEE");
        uint256 platformFee = totalFee.mul(commission).div(feeBase);
        uint256 rentFee = totalFee.sub(platformFee);
        uint256 partnerFee = platformFee.mul(partners[contract_].commission).div(feeBase);
        platformFee = platformFee.sub(partnerFee);
        _pay(detail.payment, msg.sender, detail.depositor, rentFee);
        _pay(detail.payment, msg.sender, partners[contract_].feeReceiver, partnerFee);
        _pay(detail.payment, msg.sender, beneficiary, platformFee);

        // update detail
        detail.lastRentIdx = ++totalRentCount;
        detail.endTime = block.timestamp.add(unitTime.mul(amount));
        detail.rentStatus = Enum.RentStatus.RENTED;
        tokenDetails[tokenIdx] = detail;

        // update rentals
        rentals[totalRentCount] = Rental(msg.sender, contract_, tokenId, detail.vault, detail.endTime);
        personalRentals[msg.sender][contract_].add(totalRentCount);

        emit TokenRented(msg.sender, detail.lastRentIdx, contract_, tokenId);
    }

    /// @notice cancel lend an NFToken will just make it unrentable, the exist rents won't be affected.
    /// @param contract_ The NFToken contract that issue the tokens
    /// @param tokenId The id the NFToken
    function cancelLend(address contract_, uint256 tokenId) external override {
        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        uint256 tokenIdx = tokenIdxes[tokenHash];
        require(msg.sender == tokenDetails[tokenIdx].depositor, "Undelegate can only be done by the depositor");
        require(tokenDetails[tokenIdx].rentStatus != Enum.RentStatus.UNRENTABLE, "Token is already UNRENTABLE");
        tokenDetails[tokenIdx].rentStatus = Enum.RentStatus.UNRENTABLE;

        emit LentCanceled(msg.sender, contract_, tokenId);
    }

    /// @notice check if a given token is rented or not
    function isRented(address contract_, uint256 tokenId) public override view returns  (bool) {
        bytes32 tokenHash = getTokenHash(contract_, tokenId);
        if (tokenIdxes[tokenHash] == 0) return false;

        /// @dev Undelegate A token that has never been rented will make it UNRENTABLE while
        /// detail.endTime is still 0
        return tokenDetails[tokenIdxes[tokenHash]].rentStatus != Enum.RentStatus.UNRENTABLE ||
            tokenDetails[tokenIdxes[tokenHash]].endTime >= block.timestamp;
    }

    /// @notice check all alive rentals for a given renter.
    function getAliveRentals(address renter, address contract_) public override view returns (Rental[] memory aliveRentals) {
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

    /// @notice create a vault contract for each owner
    function _createVault(address owner) internal {
        OwnerVault ov = new OwnerVault(address(this));
        ov.transferOwnership(owner);
        vaults[owner] = address(ov);
    }

    /// @notice partners setter
    function setPartners(address contract_, address feeReceiver_, uint256 commission_) external onlyOwner {
        require(commission_ <= feeBase, "Partner commission too big");
        partners[contract_] = Partner(feeReceiver_, commission_);
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

    /// @notice beneficiary setter
    function setTreasure(address beneficiary_) external onlyOwner {
        beneficiary = beneficiary_;
    }

    /// @notice add payment
    function addPayment(address payment) external onlyOwner {
        paymentContracts.add(payment);
    }

    /// @notice owners getter
    function getOwners() public view returns (address[] memory) {
        return owners.values();
    }

    /// @notice getPaymentContracts getter
    function getPaymentContracts() public view returns (address[] memory) {
        return paymentContracts.values();
    }

    /// @notice pay ether or ERC20
    function _pay(address payment, address from, address to, uint256 amount) private {
        if (amount == 0) return;
        if (payment == address(0)) {
            _payEther(payable(to), amount);
        } else {
            ERC20(payment).safeTransferFrom(from, to, amount);
        }
    }

    /// @notice pay ether
    function _payEther(address payable recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool sent,) = recipient.call{value: amount}("");
        require(sent, "SEND_ETHER_FAILED");
    }

    /// @dev Helper function to compute hash for a given token
    function getTokenHash(address contract_, uint256 tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(contract_,  tokenId));
    }
}