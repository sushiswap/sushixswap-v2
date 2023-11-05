// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {ConnextAdapter} from "../../src/adapters/ConnextAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

contract ConnextAdapterBridgeTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    ConnextAdapter public connextAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;

    uint32 opDestinationDomain = 1869640809;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public operator = address(0xbeef);
    address public owner = address(0x420);
    address public user = address(0x4201);

    function setUp() public override {
        forkMainnet();
        super.setUp();

        weth = IWETH(constants.getAddress("mainnet.weth"));
        sushi = IERC20(constants.getAddress("mainnet.sushi"));
        usdc = IERC20(constants.getAddress("mainnet.usdc"));
        usdt = IERC20(constants.getAddress("mainnet.usdt"));

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

        connextAdapter = new ConnextAdapter(
            constants.getAddress("mainnet.connext"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(connextAdapter), true);

        vm.stopPrank();
    }

    function test_RevertWhen_SendingMessage() public {
        vm.startPrank(user);
        vm.expectRevert();
        sushiXswap.sendMessage(address(connextAdapter), "");
    }

    function testFuzz_BridgeERC20(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdc), // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic usdc bridge
        vm.startPrank(user);
        usdc.safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_BridgeUSDT() public {
        uint32 amount = 1000000; // 1 usdt
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdt), user, amount);
        vm.deal(user, gasNeeded);

        // basic usdt bridge
        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdt), // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic usdc bridge
        vm.startPrank(user);
        usdt.safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(usdt),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            usdt.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdc");
    }

    function testFuzz_BridgeNative(uint256 amount) public {
        vm.assume(amount > 1 ether && amount < 250 ether); // > 1 eth & < 250 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        // basic usdt bridge
        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            NATIVE_ADDRESS, // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic usdc bridge
        vm.startPrank(user);

        sushiXswap.bridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            address(connextAdapter).balance,
            0,
            "connextAdapter should have 0 native"
        );
        assertEq(user.balance, 0, "user should have 0 native");
    }

    function test_RevertWhen_BridgeUnsupportedERC20Connext() public {
        uint32 amount = 1000000; // 1 sushi
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(sushi), user, amount);
        vm.deal(user, gasNeeded);

        // basic sushi bridge, unsupported token
        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(sushi), // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic usdc bridge
        vm.startPrank(user);
        sushi.safeIncreaseAllowance(address(sushiXswap), amount);

        vm.expectRevert();
        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(sushi),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            "", // swap payload
            "" // payload data
        );
    }

    function test_BridgeERC20WithSwapData(uint32 amount) public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: 0, // amountIn doesn't matter on dst since we use amount bridged
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute_dst
            });

        bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdc), // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic usdc bridge
        vm.startPrank(user);
        usdc.safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            rpd_encoded_dst, // swap payload
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(connextAdapter)),
            0,
            "connextAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_BridgeNativeWithSwapData() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd_dst = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: 0, // amountIn doesn't matter on dst since we use amount bridged
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute_dst
            });

        bytes memory rpd_encoded_dst = abi.encode(rpd_dst);

        // basic usdt bridge
        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            NATIVE_ADDRESS, // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic native bridge, get weth on dst
        vm.startPrank(user);

        sushiXswap.bridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            rpd_encoded_dst, // swap payload
            "" // payload data
        );

        assertEq(
            address(connextAdapter).balance,
            0,
            "connextAdapter should have 0 native"
        );
        assertEq(user.balance, 0, "user should have 0 native");
    }

    function test_RevertWhen_BridgeERC20WithNoGasPassed() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            address(usdc), // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic usdc bridge
        vm.startPrank(user);
        usdc.safeIncreaseAllowance(address(sushiXswap), amount);

        vm.expectRevert(bytes4(keccak256("NoGasReceived()")));
        sushiXswap.bridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            "", // swap payload
            "" // payload data
        );
    }

    function test_RevertWhen_BridgeNativeWithNoGasPassed() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        // basic usdt bridge
        bytes memory adapterData = abi.encode(
            opDestinationDomain, // dst domain
            address(user), // target
            address(user), // address for fallback transfers
            NATIVE_ADDRESS, // token to bridge
            amount, // amouint to bridge
            300 // slippage tolerance, 3%
        );

        // basic native bridge, get weth on dst
        vm.startPrank(user);

        vm.expectRevert(bytes4(keccak256("NoGasReceived()")));
        sushiXswap.bridge{value: amount}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(connextAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: adapterData
            }),
            user, // refundAddress
            "", // swap payload
            "" // payload data
        );
    }
}
