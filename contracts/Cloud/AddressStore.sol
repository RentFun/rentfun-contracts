// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AddressStore {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private owners;
    mapping (string=>EnumerableSet.AddressSet) private operators;
    mapping (string=>EnumerableSet.AddressSet) private stores;

    constructor(address owner) {
        owners.add(owner);
    }

    function addOperators(string memory listType, address[] memory addrs) public onlyOwner {
        for(uint i = 0; i < addrs.length; i++) {
            operators[listType].add(addrs[i]);
        }
    }

    function addStore(string memory listType, address[] memory addrs) public onlyOperator(listType) {
        for(uint i = 0; i < addrs.length; i++) {
            stores[listType].add(addrs[i]);
        }
    }

    function removeOperators(string memory listType, address[] memory addrs) public onlyOwner {
        for(uint i = 0; i < addrs.length; i++) {
            operators[listType].remove(addrs[i]);
        }
    }

    function removeStore(string memory listType, address[] memory addrs) public onlyOperator(listType) {
        for(uint i = 0; i < addrs.length; i++) {
            stores[listType].remove(addrs[i]);
        }
    }

    function getOperators(string memory listType) public view returns (address[] memory) {
        return operators[listType].values();
    }

    function getStore(string memory listType) public view returns (address[] memory) {
        return stores[listType].values();
    }

    modifier onlyOwner() {
        require(owners.contains(msg.sender), "Ownable: caller is not the owner");
        _;
    }

    modifier onlyOperator(string memory listType) {
        require(operators[listType].contains(msg.sender), "Caller is not an operator");
        _;
    }

    function getOwners() public view returns (address[] memory) {
        return owners.values();
    }

    function addOwner(address owner) public onlyOwner {
        owners.add(owner);
    }
}

