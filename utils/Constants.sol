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
    setAddress("mainnet.usdt", 0xdAC17F958D2ee523a2206206994597C13D831ec7);

    setAddress("mainnet.routeProcessor", 0xCdBCd51a5E8728E0AF4895ce5771b7d17fF71959);
    setAddress("mainnet.v2Factory", 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    setAddress("mainnet.v3Factory", 0xbACEB8eC6b9355Dfc0269C18bac9d6E2Bdc29C4F);

    setAddress("mainnet.stargateComposer", 0xeCc19E177d24551aA7ed6Bc6FE566eCa726CC8a9);
    setAddress("mainnet.stargateWidget", 0x76d4d68966728894961AA3DDC1d5B0e45668a5A6);
    setAddress("mainnet.stargateFactory", 0x06D538690AF257Da524f25D0CD52fD85b1c2173E);
    setAddress("mainnet.stargateFeeLibrary", 0x8C3085D9a554884124C998CDB7f6d7219E9C1e6F);
    setAddress("mainnet.sgeth", 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c);
    setAddress("mainnet.stargateUSDCPool", 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56);
    setAddress("mainnet.stargateETHPool", 0x101816545F6bd2b1076434B54383a1E633390A2E);
    
    setAddress("mainnet.axelarGateway", 0x4F4495243837681061C4743b74B3eEdf548D56A5);
    setAddress("mainnet.axelarGasService", 0x2d5d7d31F671F86C782533cc367F14109a082712);

    setAddress("mainnet.cctpTokenMessenger", 0xBd3fa81B58Ba92a82136038B25aDec7066af3155);

    setAddress("mainnet.squidRouter", 0xce16F69375520ab01377ce7B88f5BA8C48F8D666);
    setAddress("mainnet.squidMulticall", 0x4fd39C9E151e50580779bd04B1f7eCc310079fd3);

    // Arbitrum
    setAddress("arbitrum.axlUSDC", 0xEB466342C4d449BC9f53A865D5Cb90586f405215);
    setAddress("arbitrum.axlUSDT", 0x7f5373AE26c3E8FfC4c77b7255DF7eC1A9aF52a6);
    setAddress("arbitrum.axlETH", 0xb829b68f57CC546dA7E5806A929e53bE32a4625D);
    setAddress("arbitrum.usdt", 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
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
