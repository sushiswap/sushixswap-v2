// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../src/SushiXSwapV2.sol";
import {ISushiXSwapV2} from "../src/interfaces/ISushiXSwapV2.sol";
import {StargateAdapter} from "../src/adapters/StargateAdapter.sol";
import {IRouteProcessor} from "../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../utils/BaseTest.sol";
import "../utils/RouteProcessorHelper.sol";

import {console2} from "forge-std/console2.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

contract SushiXSwapV2Test is BaseTest {
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
            constants.getAddress("mainnet.v3Factory")
        );

        vm.startPrank(owner);
        sushiXswap = new SushiXSwapV2(routeProcessor, address(weth));

        // add operator as privileged
        sushiXswap.setPriviledge(operator, true);

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

    function testPause() public {
        vm.startPrank(owner);
        sushiXswap.pause();

        vm.startPrank(operator);
        sushiXswap.pause();
        // operator, paused, sendMesssage call
        vm.expectRevert();
        sushiXswap.sendMessage(address(stargateAdapter), abi.encode(0x01));

        sushiXswap.resume();

        vm.stopPrank();
    }

    function testRescueTokens() public {
        vm.deal(address(sushiXswap), 1 ether);
        deal(address(sushi), address(sushiXswap), 1 ether);

        // reverts if not owner
        vm.prank(operator);
        vm.expectRevert();
        sushiXswap.rescueTokens(NATIVE_ADDRESS, address(owner));

        vm.startPrank(owner);

        // native rescue
        sushiXswap.rescueTokens(NATIVE_ADDRESS, address(owner));
        assertEq(address(owner).balance, 1 ether);

        // erc20 rescue
        sushiXswap.rescueTokens(address(sushi), address(owner));
        assertEq(sushi.balanceOf(address(owner)), 1 ether);
    }

    function testOwnerGuard() public {
        vm.startPrank(operator);

        vm.expectRevert();
        sushiXswap.setPriviledge(address(0x01), true);

        vm.expectRevert();
        sushiXswap.updateAdapterStatus(address(0x01), true);

        vm.expectRevert();
        sushiXswap.updateRouteProcessor(address(0x01));
    }

    function testBridge() public {
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

    function testSwap() public {
        // basic swap 1 weth to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
          false,             // rpHasToken
          false,              // isV2
          address(weth),     // tokenIn
          address(usdc),     // tokenOut
          500,               // fee
          address(operator)  // to
        );

        vm.startPrank(operator);
        ERC20(address(weth)).approve(address(sushiXswap), 1 ether);

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(weth),
            amountIn: 1 ether,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: address(operator),
            route: computedRoute
        });

        console2.log("route-swapAndBridge");
        console2.logBytes(computedRoute);

        bytes memory rpd_encoded = abi.encode(rpd);

        sushiXswap.swap(
          rpd_encoded
        );

    }

    function testSwapAndBridge() public {
        // basic swap 1 weth to usdc and bridge
        vm.startPrank(operator);
        ERC20(address(weth)).approve(address(sushiXswap), 1 ether);

        console2.log("addresses");
        console2.log("xSwap: ", address(sushiXswap));
        console2.log("stgAdapter: ", address(stargateAdapter));
        console2.log("rp: ", address(routeProcessor));

        (uint256 gasNeeded, ) = stargateAdapter.getFee(
            111, // dstChainId
            1, // functionType
            address(operator), // receiver
            0, // gas
            0, // dustAmount
            "" // payload
        );

        bytes memory computedRoute = routeProcessorHelper.computeRoute(
          false,             // rpHasToken
          false,              // isV2
          address(weth),     // tokenIn
          address(usdc),     // tokenOut
          500,               // fee
          address(stargateAdapter)  // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor.RouteProcessorData({
            tokenIn: address(weth),
            amountIn: 1 ether,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: address(stargateAdapter),
            route: computedRoute
        });

        console2.log("route-swapAndBridge");
        console2.logBytes(computedRoute);

       bytes memory rpd_encoded = abi.encode(rpd);

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                adapter: address(stargateAdapter),
                tokenIn: address(weth),
                amountIn: 1 ether,
                to: address(0x0),
                adapterData: abi.encode(
                    111, // dstChainId - op
                    address(usdc), // token
                    1, // srcPoolId
                    1, // dstPoolId
                    0, // amount
                    0, // amountMin,
                    0, // dustAmount
                    address(operator), // receiver
                    address(0x00), // to
                    0 // gas
                )
            }),
            rpd_encoded,
            "", // _swapPayload
            "" // _payloadData
        );
    }
}


/*
0x02
0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
0x01
0xffff
0x00
0x397ff1542f962076d0bfe58ea045ffa2d347aca0
0x00
0x4bb4c1b0745ef7b4642feeccd0740dec417ca0a0



0x02
0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
0x01
0xffff
0x00
0x397ff1542f962076d0bfe58ea045ffa2d347aca0
0x00
0x000000000000000000000000000000000000beef
*/

/*
0x02
0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
0x01
0xffff
0x01
0x35644fb61afbc458bf92b15add6abc1996be5014
0x00
0x000000000000000000000000000000000000beef


0x02
0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
0x01
0xffff
0x01
0x35644fb61afbc458bf92b15add6abc1996be5014
0x00
0x26181dded63f6842053886ca0f31ef80d876628b
*/

