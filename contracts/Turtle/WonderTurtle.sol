// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract WonderTurtle is ERC721, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    /** MINTING **/
    uint256 public constant MAX_SUPPLY = 1000;
    Counters.Counter private supplyCounter;
    string private customBaseURI;

    /// treasure address
    address public treasure;

    /** StageInfo **/
    uint8 public stage = 1;
    bytes32 public merkleRoot;
    uint256 public mintPrice = 0;
    uint256 public mintLimit = 1;

    /// @notice A mapping pointing minter address to its minted number.
    mapping(uint8 => mapping(address => uint256)) public mintCounts;

    constructor(string memory customBaseURI_, bytes32 merkleRoot_, address treasure_, address contractOwner)
    ERC721("RentFun - WonderBird NFT", "WONDERBIRD")
    {
        customBaseURI = customBaseURI_;
        merkleRoot = merkleRoot_;
        treasure = treasure_;
        for (uint256 i = 1; i <= 50; i++) {
            supplyCounter.increment();
            _mint(treasure, totalSupply());
        }
        _transferOwnership(contractOwner);
    }

    function mint(uint256 count, bytes32[] calldata merkleProof) public payable nonReentrant {
        require(totalSupply() + count <= MAX_SUPPLY, "Exceeds max supply");
        require(_verifyAddress(merkleProof), "Minter is not in the whitelist");
        uint256 mintedCount = mintCounts[stage][msg.sender] + count;
        require(mintedCount <= mintLimit, "Exceeds mint limit");
        require(msg.value == mintPrice.mul(count), "Price mismatch");
        if (msg.value > 0) {
            (bool sent,) = treasure.call{value: msg.value}("");
            require(sent, "Send ether failed");
        }

        for (uint256 i = 0; i < count; i++) {
            supplyCounter.increment();
            _mint(msg.sender, totalSupply());
        }
        mintCounts[stage][msg.sender] = mintedCount;
    }

    function setBaseURI(string memory customBaseURI_) external onlyOwner {
        customBaseURI = customBaseURI_;
    }

    /// @notice update merkleRoot and mintPrice and mintLimit
    function UpdateStage(uint8 stage_, bytes32 merkleRootHash, uint256 price, uint256 limit) external onlyOwner {
        stage = stage_;
        merkleRoot = merkleRootHash;
        mintPrice = price;
        mintLimit = limit;
    }

    function tokenURI(uint256 tokenId) public view override
    returns (string memory)
    {
        return string(abi.encodePacked(super.tokenURI(tokenId), ".token.json"));
    }

    function totalSupply() public view returns (uint256) {
        return supplyCounter.current();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return customBaseURI;
    }

    /// @notice Verify merkle proof of the address
    function _verifyAddress(bytes32[] calldata _merkleProof) private view returns (bool) {
        if (merkleRoot == bytes32(0)) return true;

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }
}