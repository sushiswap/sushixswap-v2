// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {CCTPAdapter} from "../../src/adapters/CCTPAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

contract CCTPAdapterBridgeTest is BaseTest {
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

    function test_RevertWhen_SendingMessage() public {
        vm.startPrank(user);
        vm.expectRevert();
        sushiXswap.sendMessage(address(cctpAdapter), "");
    }

    function test_BridgeUSDC() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        // approve sushiXswap to bridge usdc
        vm.startPrank(user);
        usdc.approve(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    amount, // amount
                    user // to
                )
            }),
            "", // swap payload
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapter)),
            0,
            "cctpAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_RevertWhen_BridgeNative() public {
        uint64 amount = 1 ether; // 1 eth
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        uint256 valueToSend = amount + gasNeeded;
        vm.deal(user, valueToSend);

        // try bridging native
        vm.startPrank(user);

        vm.expectRevert(bytes4(keccak256("NoUSDCToBridge()")));
        sushiXswap.bridge{value: valueToSend}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    amount, // amount
                    user // to
                )
            }),
            "", // swap payload
            "" // payload data
        );
    }

    function test_BridgeUSDCWithSwapData() public {
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

        // basic usdc bridge
        vm.startPrank(user);
        usdc.approve(address(sushiXswap), amount);

        sushiXswap.bridge{value: gasNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    amount, // amount
                    user // to
                )
            }),
            rpd_encoded_dst, // swap payload
            "" // payload data
        );

        assertEq(
            usdc.balanceOf(address(cctpAdapter)),
            0,
            "cctpAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_RevertWhen_BridgeUSDCWithNoGasPassed() public {
        uint32 amount = 1000000; // 1 usdc
        uint64 gasNeeded = 0.1 ether; // eth for gas to pass

        deal(address(usdc), user, amount);
        vm.deal(user, gasNeeded);

        // basic usdc bridge, mint axlUSDC on otherside
        vm.startPrank(user);
        usdc.approve(address(sushiXswap), amount);

        vm.expectRevert(bytes4(keccak256("NothingReceived()")));
        sushiXswap.bridge(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(cctpAdapter),
                tokenIn: address(usdc),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    StringToBytes32.toBytes32("arbitrum"), // destinationChain
                    address(cctpAdapter), // destinationAddress
                    amount, // amount
                    user // to
                )
            }),
            "", // swap payload
            "" // payload data
        );
    }
}
