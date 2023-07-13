// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "forge-std/Vm.sol";

contract Constants {
  mapping(string => address) private addressMap;
  mapping(string => bytes32) private pairCodeHash;
  //byteCodeHash for trident pairs

  string[] private addressKeys;

  constructor() {
    // Mainnet
    setAddress("mainnet.weth", 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    setAddress("mainnet.sushi", 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
    setAddress("mainnet.usdc", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    setAddress("mainnet.routeProcessor", 0x827179dD56d07A7eeA32e3873493835da2866976);
    setAddress("mainnet.v2Factory", 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    setAddress("mainnet.v3Factory", 0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F);

    setAddress("mainnet.stargateRouter", 0x8731d54E9D02c286767d56ac03e8037C07e01e98);
    setAddress("mainnet.stargateWidget", 0x76d4d68966728894961AA3DDC1d5B0e45668a5A6);
    setAddress("mainnet.stargateFactory", 0x06D538690AF257Da524f25D0CD52fD85b1c2173E);
    setAddress("mainnet.stargateFeeLibrary", 0x8C3085D9a554884124C998CDB7f6d7219E9C1e6F);
    setAddress("mainnet.sgeth", 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c);
    setAddress("mainnet.stargateUSDCPool", 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56);
    setAddress("mainnet.stargateETHPool", 0x101816545F6bd2b1076434B54383a1E633390A2E);
    
    setAddress("mainnet.axelarGateway", 0x4F4495243837681061C4743b74B3eEdf548D56A5);
    setAddress("mainnet.axelarGasService", 0x2d5d7d31F671F86C782533cc367F14109a082712);
  }

  function initAddressLabels(Vm vm) public {
    for (uint256 i = 0; i < addressKeys.length; i++) {
      string memory key = addressKeys[i];
      vm.label(addressMap[key], key);
    }
  }

  function setAddress(string memory key, address value) public {
    require(addressMap[key] == address(0), string(bytes.concat("address already exists: ", bytes(key))));
    addressMap[key] = value;
    addressKeys.push(key);
  }

  function getAddress(string calldata key) public view returns (address) {
    require(addressMap[key] != address(0), string(bytes.concat("address not found: ", bytes(key))));
    return addressMap[key];
  }

  function getPairCodeHash(string calldata key) public view returns (bytes32) {
    require(pairCodeHash[key] != "", string(bytes.concat("pairCodeHash not found: ", bytes(key))));
    return pairCodeHash[key];
  }
}
