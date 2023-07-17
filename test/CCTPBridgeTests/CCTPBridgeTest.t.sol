// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {CCTPAdapter} from "../../src/adapters/CCTPAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import "../../utils/BaseTest.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

import {console2} from "forge-std/console2.sol";

contract CCTPBridgeTest is BaseTest {
  SushiXSwapV2 public sushiXswap;
  CCTPAdapter public cctpAdapter;
  IRouteProcessor public routeProcessor;
  
  IWETH public weth;
  ERC20 public sushi;
  ERC20 public usdc;

  address constant NATIVE_ADDRESS =
    0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address public operator = address(0xbeef);
  address public owner = address(0x420);
  address public user = address(0x4201);

  function setUp() public override {
    forkMainnet();
    super.setUp();

    weth = IWETH(constants.getAddress("mainnet.weth"));
    sushi = ERC20(constants.getAddress("mainnet.sushi"));
    usdc = ERC20(constants.getAddress("mainnet.usdc"));

    routeProcessor = IRouteProcessor(
      constants.getAddress("mainnet.routeProcessor")
    );

    vm.startPrank(owner);
    sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

    // add operator as privileged
    sushiXswap.setPrivileged(operator, true);

    // setup axelar adapter
    cctpAdapter = new CCTPAdapter(
      constants.getAddress("mainnet.axelarGateway"),
      constants.getAddress("mainnet.axelarGasService"),
      constants.getAddress("mainnet.cctpTokenMessenger"),
      constants.getAddress("mainnet.routeProcessor"),
      constants.getAddress("mainnet.usdc")
    );
    sushiXswap.updateAdapterStatus(address(cctpAdapter), true);

    vm.stopPrank();
  }

  function test_BridgeUSDC() public {
    uint32 amount = 1000000; // 1 usdc
    uint64 gasNeeded = 0.1 ether; // eth for gas to pass

    deal(address(usdc), user, amount);
    vm.deal(user, gasNeeded);

    // approve sushiXswap to spend usdc
    vm.startPrank(user);
    usdc.approve(address(sushiXswap), amount);

    sushiXswap.bridge{value: gasNeeded}(
      ISushiXSwapV2.BridgeParams({
        refId: 0x0000,
        adapter: address(cctpAdapter),
        tokenIn: address(usdc),
        amountIn: amount,
        to: address(0x0),
        adapterData: abi.encode(
          StringToBytes32.toBytes32("arbitrum"),     // destinationChain
          address(cctpAdapter), // destinationAddress
          amount,         // amount
          user            // refundAddress
        )
      }),
      "", // swap payload
      ""  // payload data
    );
  }
}