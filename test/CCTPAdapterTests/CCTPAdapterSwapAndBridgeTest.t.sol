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
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

import {console2} from "forge-std/console2.sol";

contract CCTPAdapterSwapAndBridgeTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    CCTPAdapter public cctpAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

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

    function test_SwapFromERC20ToUSDCAndBridge() public {
        uint64 amount = 1 ether; // 1 weth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(weth), user, amount);
        vm.deal(user, gasNeeded);

        // swap 1 weth to usdc and bridge
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdc), // tokenOut
            500, // fee
            address(cctpAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(cctpAdapter),
                route: computedRoute
            });
        
        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        ERC20(address(weth)).approve(address(sushiXswap), amount);

        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: address(weth),
                amountIn: amount,
                to: address(user),
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    0, // amount - 0 since swap first
                    user // refundAddress
                )
            }),
            rpd_encoded, // swap data
            "", // swap payload
            "" // payload data
        );

        assertEq(usdc.balanceOf(address(cctpAdapter)), 0, "cctpAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(weth.balanceOf(address(cctpAdapter)), 0, "cctpAdapter should have 0 weth");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_SwapFromNativeToUSDCAndBridge() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        // swap 1 weth to usdc and bridge
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdc), // tokenOut
            500, // fee
            address(cctpAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: address(cctpAdapter),
                route: computedRoute
            });
        
        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        sushiXswap.swapAndBridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: address(weth), // doesn't matter what you put here
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    0, // amount - 0 since swap first
                    user // refundAddress
                )
            }),
            rpd_encoded, // swap data
            "", // swap payload
            "" // payload data
        );

        assertEq(usdc.balanceOf(address(cctpAdapter)), 0, "cctpAdapter should have 0 usdc");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(address(cctpAdapter).balance, 0, "cctpAdapter should have 0 eth");
        assertEq(user.balance, 0, "user should have 0 eth");
    }

    function test_RevertWhen_SwapFromUSDCToERC20AndBridge() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        // swap 1 weth to usdc and bridge
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false, // rpHasToken
            false, // isV2
            address(usdc), // tokenIn
            address(weth), // tokenOut
            500, // fee
            address(cctpAdapter) // to
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: address(cctpAdapter),
                route: computedRoute
            });
        
        bytes memory rpd_encoded = abi.encode(rpd);

        vm.startPrank(user);
        usdc.approve(address(sushiXswap), amount);

        vm.expectRevert(bytes4(keccak256("NoUSDCToBridge()")));
        sushiXswap.swapAndBridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: address(usdc), // doesn't matter what you put here
                amountIn: amount,
                to: address(user),
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    0, // amount - 0 since swap first
                    user // refundAddress
                )
            }),
            rpd_encoded, // swap data
            "", // swap payload
            "" // payload data
        );
    }
}
