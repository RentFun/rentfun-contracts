// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract WonderBird is ERC721Enumerable, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;

    /** MINTING **/
    uint256 public constant MAX_SUPPLY = 1000;
    uint256 public availableTokenNum;
    string private _baseTokenURI;
    mapping(uint256 => uint256) private _availableTokens;

    /** tokenURI **/
    string public constant baseExtension = ".json";
    bool public revealed = false;
    string[] public neckTraits;
    mapping(uint256 => uint8) public neckTraitIdxes;

    /// treasure address
    address public constant treasure = 0x3353b44be83197747eB6a4b3B9d2e391c2A357d5;

    /** StageInfo **/
    uint8 public stage = 1;
    bytes32 public merkleRoot;
    uint256 public mintPrice = 0;
    uint256 public mintLimit = 1;
    /// @notice A mapping pointing minter address to its minted number.
    /// @dev stage => minter => count
    mapping(uint8 => mapping(address => uint256)) public mintCounts;

    /** EVENTS **/
    event stageUpdated(uint8 stage, bytes32 merkleRoot, uint256 mintPrice, uint256 mintLimit);

    constructor(string memory baseTokenURI, bytes32 merkleRoot_, address contractOwner)
    ERC721("RentFun - WonderBird NFT", "WONDERBIRD") {
        neckTraits = ['Arbitrum', 'Diamond', 'TreasureDAO', 'Ethereum', 'Nova'];
        availableTokenNum = MAX_SUPPLY;
        _baseTokenURI = baseTokenURI;
        merkleRoot = merkleRoot_;
        for (uint256 i = 0; i < 50; i++) {
            uint256 tokenId = getRandomTokenId(availableTokenNum);
            --availableTokenNum;
            _safeMint(treasure, tokenId);
        }
        _transferOwnership(contractOwner);
    }

    function mint(uint256 numToMint, bytes32[] calldata merkleProof) public payable nonReentrant {
        require(numToMint > 0, "Need to mint at least one token");
        require(availableTokenNum >= numToMint, "Minting more tokens than available");
        require(_verifyAddress(merkleProof), "Minter is not in the whitelist");
        uint256 mintedCount = mintCounts[stage][msg.sender] + numToMint;
        require(mintedCount <= mintLimit, "Exceeds mint limit");
        require(msg.value == mintPrice.mul(numToMint), "Price mismatch");
        if (msg.value > 0) {
            (bool sent,) = treasure.call{value: msg.value}("");
            require(sent, "Send ether failed");
        }

        for (uint256 i = 0; i < numToMint; i++) {
            uint256 tokenId = getRandomTokenId(availableTokenNum);
            --availableTokenNum;
            _safeMint(msg.sender, tokenId);
        }
        mintCounts[stage][msg.sender] = mintedCount;
    }

    function setBaseURI(string memory baseTokenURI) external onlyOwner {
        _baseTokenURI = baseTokenURI;
    }

    function reveal() external onlyOwner {
        revealed = true;
    }

    /// @notice update stage, merkleRoot, mintPrice and mintLimit
    function UpdateStage(bytes32 merkleRootHash, uint256 price, uint256 limit) external onlyOwner {
        stage++;
        merkleRoot = merkleRootHash;
        mintPrice = price;
        mintLimit = limit;
        emit stageUpdated(stage, merkleRoot, mintPrice, mintLimit);
    }

    /// @notice upgrade tokens
    function upgrade(uint256[] memory tokenIds, uint8[] memory neckIndexes) external onlyOwner {
        require(tokenIds.length == neckIndexes.length, 'Length mismatch');

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _requireMinted(tokenIds[i]);
            require(neckIndexes[i] > 0 && neckIndexes[i] < neckTraits.length+1, 'Wrong neck trait value');
            neckTraitIdxes[tokenIds[i]] = neckIndexes[i];
        }
    }

    function getRandomTokenId(uint availableNum) public returns (uint256) {
        uint256 randomNum = uint256(keccak256(abi.encodePacked(
                tx.gasprice, block.number, block.timestamp, block.difficulty, blockhash(block.number - 1),
                address(this), availableNum)));
        uint256 randomIndex = randomNum % availableNum + 1;
        return getAvailableTokenAtIndex(randomIndex, availableNum);
    }

    function getAvailableTokenAtIndex(uint256 indexToUse, uint availableNum) internal returns (uint256) {
        uint256 valAtIndex = _availableTokens[indexToUse];
        uint256 result;
        if (valAtIndex == 0) {
            // This means the index itself is still an available token
            result = indexToUse;
        } else {
            // This means the index itself is not an available token, but the val at that index is.
            result = valAtIndex;
        }

        uint256 lastIndex = availableNum;
        uint256 lastValInArray = _availableTokens[lastIndex];
        if (indexToUse != lastIndex) {
            // Replace the value at indexToUse, now that it's been used.
            // Replace it with the data from the last index in the array, since we are going to decrease the array size afterwards.
            if (lastValInArray == 0) {
                // This means the index itself is still an available token
                _availableTokens[indexToUse] = lastIndex;
            } else {
                // This means the index itself is not an available token, but the val at that index is.
                _availableTokens[indexToUse] = lastValInArray;
            }
        }
        if (lastValInArray != 0) {
            // Gas refund courtsey of @dievardump
            delete _availableTokens[lastIndex];
        }

        return result;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        if (!revealed) {
            return string(abi.encodePacked(_baseTokenURI, 'unrevealed', baseExtension));
        } else if (neckTraitIdxes[tokenId] != 0) {
            return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), '_', neckTraits[neckTraitIdxes[tokenId]-1], baseExtension));
        } else {
            return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), baseExtension));
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Verify merkle proof of the address
    function _verifyAddress(bytes32[] calldata _merkleProof) private view returns (bool) {
        if (merkleRoot == bytes32(0)) return true;

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }
}