// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {StargateAdapter} from "../../src/adapters/StargateAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StdUtils} from "forge-std/StdUtils.sol";

contract SushiXSwapBaseTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    StargateAdapter public stargateAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    ERC20 public sushi;
    ERC20 public usdc;
    
    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public operator = address(0xbeef);
    address public owner = address(0x420);

    function setUp() public override {
        forkMainnet();
        super.setUp();

        weth = IWETH(constants.getAddress("mainnet.weth"));
        sushi = ERC20(constants.getAddress("mainnet.sushi"));
        usdc = ERC20(constants.getAddress("mainnet.usdc"));

        vm.deal(address(operator), 100 ether);
        deal(address(weth), address(operator), 100 ether);
        deal(address(usdc), address(operator), 1 ether);
        deal(address(sushi), address(operator), 1000 ether);

        routeProcessor = IRouteProcessor(
            constants.getAddress("mainnet.routeProcessor")
        );
        routeProcessorHelper = new RouteProcessorHelper(
            constants.getAddress("mainnet.v2Factory"),
            constants.getAddress("mainnet.v3Factory"),
            address(routeProcessor),
            address(weth)
        );

        vm.startPrank(owner);
        sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

        // add operator as privileged
        sushiXswap.setPrivileged(operator, true);

        // setup stargate adapter
        stargateAdapter = new StargateAdapter(
            constants.getAddress("mainnet.stargateRouter"),
            constants.getAddress("mainnet.stargateWidget"),
            constants.getAddress("mainnet.sgeth"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(stargateAdapter), true);

        vm.stopPrank();
    }

    function testBridgeERC20() public {
        // basic 1 usdc bridge
        vm.startPrank(operator);
        usdc.approve(address(sushiXswap), 1 ether);

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            address(operator), // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                adapter: address(stargateAdapter),
                tokenIn: address(usdc),
                amountIn: 1000000,
                to: address(0x0),
                adapterData: abi.encode(
                    111, // dstChainId - op
                    address(usdc), // token
                    1, // srcPoolId
                    1, // dstPoolId
                    1000000, // amount
                    0, // amountMin,
                    0, // dustAmount
                    address(operator), // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            "", // _swapPayload
            "" // _payloadData
        );

        // assertions for bridge call
    }

    function testBridgeWeth() public {
      
    }

    function testBridgeNative() public {
      // bridge 1 eth
      vm.startPrank(operator);

      (uint256 gasNeeded, ) = stargateAdapter.getFee(
        111,
        1,
        address(operator),
        0,
        0,
        ""
      );

      uint256 valueToSend = gasNeeded + 1 ether;
      sushiXswap.bridge{value: valueToSend}(
        ISushiXSwapV2.BridgeParams({
          adapter: address(stargateAdapter),
          tokenIn: NATIVE_ADDRESS,
          amountIn: 1 ether,
          to: address(0x0),
          adapterData: abi.encode(
            111, // dstChainId - op
            NATIVE_ADDRESS, // token
            13, // srcPoolId
            13, // dstPoolId
            1 ether, // amount
            0, // amountMin,
            0, // dustAmount
            address(operator), // receiver
            address(0x00), // to
            0 // gas
          )
        }),
        "", // _swapPayload
        "" // _payloadData
      );
    }

}