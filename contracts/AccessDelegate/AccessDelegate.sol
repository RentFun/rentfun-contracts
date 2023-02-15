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
    address public feeReceiver;
    address public vault;

    struct NFToken {
        address contract_;
        uint256 tokenId;
    }

    /// @notice Delegation type
    enum TokenStatus {
        NONE,
        RENTABLE,
        UNRENTABLE,
        WITHDRAWN
    }
    struct TokenDetail {
        address depositor;
        NFToken token;
        uint256 unitFee;
        uint256 totalRentCount;
        uint256 totalFee;
        uint256 totalTime;
        TokenStatus status;
    }

    struct Partner {
        address feeReceiver;
        uint256 commission;
        uint256 totalFee;
    }

    EnumerableSet.AddressSet public contractSet;
    /// @notice A mapping pointing token's contract address to partner structs
    mapping(address => Partner) public partners;

    constructor(address feeReceiver_, uint256 unitTime_, uint256 commission_) {
        // The commission cannot exceed 10%
        require(commission_ <= 1000, "commission too big");
        feeReceiver = feeReceiver_;
        unitTime = unitTime_;
        commission = commission_;
    }

    /// @notice An incrementing counter to create unique ids for each escrow deposit created
    uint256 public nextTokenIdx = 1;

    /// @notice A mapping pointing tokenId to TokenDetail structs
    mapping(uint256 => TokenDetail) public tokenDetails;

    /// @notice A mapping pointing token hash to tokenId
    mapping(byte32 => uint256) public tokenIdxes;

    struct Rent {
        address renter;
        NFToken token;
        uint256 amount;
        uint256 unitTime;
        uint256 unitFee;
        uint256 rentFee;
        uint256 endTime;
    }

    /// @notice A mapping pointing tokenIdx to its rentIdx
    mapping(uint256 => uint256) internal rentIdxes;

    /// @notice A mapping pointing rentId to its rent
    /// dev rentIdx -> rent
    mapping(uint256 => Rent) internal rents;

    /// @notice A double mapping from rentIdx to contract to renter to keep the most lasting rent
    /// @dev renter -> contract -> rentIdx
    mapping(address => mapping(address => uint256)) internal lastingRents;

    /// @notice Emitted on each token lent
    event TokenLent(address indexed depositer, address indexed contract_, uint256 tokenId,
        uint256 endTime, uint256 unitFee);

    /// @notice Emitted on each token rent
    event TokenRented(address indexed renter, uint256 tokenIdx, uint256 rentIdx);

    /// @notice Emitted on each token withdraw
    event TokenWithdrawn(address indexed depositor, address indexed contract_, uint256 tokenId);

    /// @notice Emitted on each token lent cancel
    event LentCancelled(address indexed depositor, address indexed contract_, uint256 tokenId);

    /**
     * ----------- DEPOSIT CREATION AND BURN -----------
     */

    /// @notice Use this to deposit a timelocked escrow and create a liquid claim on its delegation rights
    /// @param contract_ The collection contract to deposit from
    /// @param tokenId The tokenId from the collection to deposit
    /// @param expiration The timestamp that the liquid delegate will expire and return the escrowed NFT
    /// @param referrer Set to the zero address by default, alternate frontends can populate this to receive half the creation fee
    function lendToken(address contract_, uint256 tokenId, uint256 unitFee) external {
        ERC721(contract_).transferFrom(msg.sender, vault, tokenId);
        bytes32 tokenHash = _tokenHash(contract_, tokenId);
        uint256 idx = tokenIdxes[tokenHash];
        TokenDetail detail;
        if (idx == 0) {
            // The token comes for the first time
            idx = nextTokenIdx++;
            detail = TokenDetail({
                depositor: msg.sender,
                token: NFToken(contract_, tokenId),
                unitFee: unitFee,
                totalRentCount: 0,
                totalFee: 0,
                totalTime: 0,
                TokenStatus: TokenStatus.RENTABLE
            });
            tokenIdxes[tokenHash] = idx;
        } else {
            // The token has ever been delegated
            detail = tokenDetails[id];
            detail.depositor = msg.sender;
            detail.unitFee = unitFee;
            detail.status = TokenStatus.RENTABLE;
        }
        tokenDetails[idx] = detail;
        contractSet.add(contract_);

        emit TokenLent(msg.sender, contract_, tokenId, unitFee);
    }

    function rentToken(uint256 tokenIdx, uint256 amount) external payable {
        TokenDetail detail = tokenDetails[tokenIdx];
        require(detail.status == TokenStatus.RENTABLE, "Token is unrentable");
        require(amount > 0, "Rent period too short");
        uint256 rentIdx = rentIdxes[tokenIdx];
        if (rentIdx != 0) {
            // The token has ever been rented
            require(rents[rentIdx].endTime <= block.timestamp, "Token is already being rented");
        }

        uint256 totalTime = unitTime.mul(amount);
        uint256 totalFee = unitFee.mul(amount);
        uint256 platformFee = totalFee.mul(commission).div(feeBase);
        uint256 rentFee = totalFee.sub(platformFee);
        _pay(detail.depositor, rentFee, true);
        Partner ptn = partners[detail.token.contract_];
        if (ptn.commission != 0) {
            uint256 partnerFee = platformFee.mul(ptn.commission).div(feeBase);
            platformFee = platformFee.sub(partnerFee);
            _pay(feeReceiver, platformFee, true);
            _pay(ptn.feeReceiver, partnerFee, true);
            ptn.totalFee = ptn.totalFee.add(partnerFee);
            partners[detail.token.contract_] = ptn;
        }

        detail.totalRentCount = detail.totalRentCount.add(1);
        detail.totalFee = detail.totalFee.add(totalFee);
        detail.totalTime = detail.totalTime.add(totalTime);
        tokenDetails[tokenIdx] = detail;

        Rent rent = Rent({
            renter: msg.sender,
            token: detail.token,
            amount: amount,
            unitFee: detail.unitFee,
            unitTime: unitTime,
            rentFee: rentFee,
            endTime: block.timestamp.add(unitTime.mul(amount))
        });
        rentIdxes[tokenIdx] = ++rentIdx;
        rents[rentIdx] = rent;

        // update the most lasting rent
        uint256 lastRentIdx = lastingRents[msg.sender][detail.token.contract_];
        if (lastRentIdx == 0) {
            lastingRents[msg.sender][detail.token.contract_] = rentIdx;
        } else {
            Rent lastRent = rents[lastRentIdx];
            if (rent.endTime >= lastRent.endTime) {
                lastingRents[msg.sender][detail.token.contract_] = rentIdx;
            }
        }

        emit TokenRented(msg.sender, tokenIdx, rentIdx);
    }

    /// @notice withdraw can only be done as there're no rent exist
    /// @param tokenIdx The idx of the NFToken
    function withdraw(uint256 tokenIdx) external {
        TokenDetail detail = tokenDetails[tokenIdx];
        require(msg.sender == detail.depositor, "Token can only be withdrawed by the depositor");
        require(detail.status != TokenStatus.WITHDRAWN, "Token has already been withdrawed");

        uint256 rentIdx = rentIdxes[tokenIdx];
        if (rentIdx != 0) {
            // The token has ever been rented
            require(rents[rentIdx].endTime <= block.timestamp, "Token is being rented");
        }

        ERC721VaultInterface(vault).transferTo(detail.token.contract_, detail.token.tokenId, msg.sender);
        detail.status = TokenStatus.WITHDRAWN;
        tokenDetails[tokenIdx] = detail;

        emit TokenWithdrawn(msg.sender, detail.token.contract_, detail.token.tokenId);
    }

    /// @notice cancelLend will just make the token unrentable, the exist rents won't be affected.
    /// @param tokenIdx The idx of the NFToken
    function cancelLend(uint256 tokenIdx) external {
        TokenDetail detail = tokenDetails[tokenIdx];
        require(msg.sender == detail.depositor, "Lent can only be cancelled by the depositor");
        require(detail.status == TokenStatus.RENTABLE, "Lent can only be cancelled when it is rentable");

        detail.status = TokenStatus.UNRENTABLE;
        tokenDetails[tokenIdx] = detail;

        emit LentCancelled(msg.sender, detail.token.contract_, detail.token.tokenId);
    }

    /// @notice check if a given address is renting a token for a given NFT contract.
    function checkRent(address renter, address contract_) external view returns (uint256 tokenId, uint256 endTime) {
        uint256 rentIdx = lastingRents[renter][contract_];
        if (rentIdx == 0) {
            return (0, 0);
        }

        Rent rent = rents[rentIdx];
        return (rent.token.tokenId, rent.endTime);
    }

    /// @notice contractSet setter
    function setPartners(address contract_, address feeReceiver_, uint256 commission_) onlyOwner {
        require(commission_ <= feeBase, "Partner commission too big");
        Partner ptn = partners[contract_];
        ptn.feeReceiver = feeReceiver_;
        ptn.commission_ = ptn.commission_;
        partners[contract_] = ptn;
    }

    /// @notice LeastRentPeriod setter
    function setLeastRentPeriod(uint256 unitTime_) onlyOwner {
        unitTime = unitTime_;
    }

    /// @notice LeastRentPeriod getter
    function unitTime() external view returns (uint256) {
        return unitTime;
    }

    /// @notice Commission setter
    function setCommission(uint256 commission_) onlyOwner {
        require(commission_ <= 1000, "Commission too big");
        commission = commission_;
    }

    /// @notice Commission getter
    function commission() external view returns (uint256) {
        return commission;
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
    function _tokenHash(address contract_, uint256 tokenId) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(contract_,  tokenId));
    }
}