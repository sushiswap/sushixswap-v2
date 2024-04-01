// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {RouterNitroAdapter} from "../../src/adapters/RouterNitroAdapter.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "../../src/interfaces/ISushiXSwapV2Adapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StringToBytes32, Bytes32ToString} from "../../src/utils/Bytes32String.sol";
import {StringToAddress, AddressToString} from "../../src/utils/AddressString.sol";

contract MockNitroAssetForwarder {
    using SafeERC20 for IERC20;

    RouterNitroAdapter _routerNitroAdapter;
    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setNitroAdapter(address __routerNitroAdapter) external {
        _routerNitroAdapter = RouterNitroAdapter(payable(__routerNitroAdapter));
    }

    function handleMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external {
        if (address(_routerNitroAdapter) == address(0)) revert ("_routerNitroAdapter not set");
        if (tokenSent == NATIVE_ADDRESS) address(_routerNitroAdapter).call{value: amount}("");
        else IERC20(tokenSent).safeTransfer(address(_routerNitroAdapter), amount);

       _routerNitroAdapter.handleMessage(
            tokenSent,
            amount, 
            message
        );
    }

    receive() external payable {}
}

contract RouterNitroAdapterExecutesTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    RouterNitroAdapter public routerNitroAdapter;
    MockNitroAssetForwarder public nitroAssetForwarder;
    AirdropPayloadExecutor public airdropExecutor;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;

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

        // setup router nitro adapter
        nitroAssetForwarder = new MockNitroAssetForwarder();
        routerNitroAdapter = new RouterNitroAdapter(
            address(nitroAssetForwarder),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );

        nitroAssetForwarder.setNitroAdapter(address(routerNitroAdapter));
        
        sushiXswap.updateAdapterStatus(address(routerNitroAdapter), true);

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_ReceiveERC20SwapToERC20() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    function test_ReceiveExtraERC20SwapToERC20UserReceivesExtra() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC
        deal(address(usdc), address(routerNitroAdapter), 1); // nitro adapter receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(address(usdc), amount, mockPayload);

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 1, "user should have extra usdc");
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    function test_ReceiveUSDTSwapToERC20() public {
        uint32 amount = 1000000; // 1 usdt

        deal(address(usdt), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC

        // receive 1 USDD and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdt),
            address(usdc),
            100,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(address(usdt), amount, mockPayload);

        assertEq(
            usdt.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdt"
        );
        assertEq(
            usdt.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), 0, "user should have 0 usdt");
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
    }

    function test_ReceiveERC20AndNativeSwapToERC20ReturnDust() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 nativeAmount = 0.001 ether;

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC
        vm.deal(address(routerNitroAdapter), nativeAmount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
        assertEq(
            address(nitroAssetForwarder).balance,
            0,
            "nitroAssetForwarder should have 0 eth"
        );
        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveERC20SwapToNative() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRouteNativeOut(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: NATIVE_ADDRESS,
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(address(usdc), amount, mockPayload);
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 eth"
        );
        assertEq(
            address(nitroAssetForwarder).balance,
            0,
            "nitroAssetForwarder should have 0 eth"
        );
        assertGt(user.balance, 0, "user should have > 0 eth");
    }

    function test_ReceiveERC20NotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage{gas: 100000}(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDTNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 usdt

        deal(address(usdt), address(nitroAssetForwarder), amount); // nitro asset forwarder receives usdt

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdt),
            address(usdc),
            100,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdt),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage{gas: 100000}(
            address(usdt),
            amount,
            mockPayload
        );

        assertEq(
            usdt.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdt"
        );
        assertEq(
            usdt.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdt"
        );
        assertEq(usdt.balanceOf(user), amount, "user should have all usdt");
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_ReceiveERC20AndNativeNotEnoughGasForSwap() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 nativeAmount = 0.001 ether; //

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitro asset forwarder receives USDC
        vm.deal(address(routerNitroAdapter), nativeAmount);

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        // sending 120k because some gas may be used for asset forwarder to nitro adapter call
        nitroAssetForwarder.handleMessage{gas: 120000}(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            address(nitroAssetForwarder).balance,
            0,
            "nitroAssetForwarder should have 0 eth"
        );
        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 eth"
        );
        assertEq(user.balance, nativeAmount, "user should have all dust eth");
    }

    function test_ReceiveERC20EnoughForGasNoSwapOrPayloadData() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitroAssetForwarder receives USDC

        bytes memory mockPayload = abi.encode(
            user, // to
            "", // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(address(usdc), amount, mockPayload);

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwap() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitroAssetForwarder receives USDC

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(weth),
            address(usdc),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveUSDCAndNativeFailedSwapMinimumGasSent() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 dustAmount = 0.2 ether;

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitroAssetForwarder receives USDC
        vm.deal(address(routerNitroAdapter), dustAmount);

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(weth),
            address(usdc),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        // sending 120k because some gas may be used for asset forwarder to nitro adapter call
        nitroAssetForwarder.handleMessage{gas: 120000}(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(
            address(nitroAssetForwarder).balance,
            0,
            "nitroAssetForwarder should have 0 eth"
        );
        assertEq(
            address(routerNitroAdapter).balance,
            0,
            "routerNitroAdapter should have 0 eth"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(user.balance, dustAmount, "user should have all the dust");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapFromOutOfGas() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitroAssetForwarder receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage{gas: 120000}(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20FailedSwapSlippageCheck() public {
        uint32 amount = 1000000; // 1 USDC

        deal(address(usdc), address(nitroAssetForwarder), amount); // nitroAssetForwarder receives USDC

        // receive 1 USDC and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        // attempt to swap usdc to weth with max amountOutMin
        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(usdc),
                amountIn: amount,
                tokenOut: address(weth),
                amountOutMin: type(uint256).max,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory mockPayload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            mockPayload
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_ReceiveERC20SwapToERC20AirdropERC20FromPayload()
        public
    {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(nitroAssetForwarder), amount); // amount nitroAssetForwarder receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            address(airdropExecutor)
        );

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            abi.encode(
                address(user), // to
                abi.encode(
                    IRouteProcessor.RouteProcessorData({
                        tokenIn: address(usdc),
                        amountIn: amount,
                        tokenOut: address(weth),
                        amountOutMin: 0,
                        to: address(airdropExecutor),
                        route: computedRoute
                    })
                ), // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(weth),
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            )
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertGt(
            weth.balanceOf(user1),
            0,
            "user1 should have > 0 weth from airdrop"
        );
        assertGt(
            weth.balanceOf(user2),
            0,
            "user2 should have > 0 weth from airdrop"
        );
    }

    function test_ReceiveERC20SwapToERC20FailedAirdropFromPayload()
        public
    {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(nitroAssetForwarder), amount); // amount nitroAssetForwarder receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            true,
            false,
            address(usdc),
            address(weth),
            500,
            address(airdropExecutor)
        );

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            abi.encode(
                address(user), // to
                abi.encode(
                    IRouteProcessor.RouteProcessorData({
                        tokenIn: address(usdc),
                        amountIn: amount,
                        tokenOut: address(weth),
                        amountOutMin: 0,
                        to: address(airdropExecutor),
                        route: computedRoute
                    })
                ), // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(user), // using user for token to airdrop so it fails
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            )
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            weth.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 weth"
        );
        assertEq(
            weth.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            usdc.balanceOf(user1),
            0,
            "user1 should have 0 usdc from airdrop"
        );
        assertEq(
            usdc.balanceOf(user2),
            0,
            "user2 should have 0 usdc from airdrop"
        );
    }

    function test_ReceiveERC20AirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(nitroAssetForwarder), amount); // amount nitroAssetForwarder receives

        // airdrop all the usdc to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            abi.encode(
                address(user), // to
                "", // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(usdc),
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            )
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertGt(
            usdc.balanceOf(user1),
            0,
            "user1 should have > 0 usdc from airdrop"
        );
        assertGt(
            usdc.balanceOf(user2),
            0,
            "user2 should have > 0 usdc from airdrop"
        );
    }

    function test_ReceiveERC20FailedAirdropFromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(nitroAssetForwarder), amount); // amount nitroAssetForwarder receives

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        nitroAssetForwarder.handleMessage(
            address(usdc),
            amount,
            abi.encode(
                address(user), // to
                "", // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(weth), // using weth for token to airdrop so it fails
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            )
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            usdc.balanceOf(user1),
            0,
            "user1 should have 0 usdc from airdrop"
        );
        assertEq(
            usdc.balanceOf(user2),
            0,
            "user2 should have 0 usdc from airdrop"
        );
    }

    function test_ReceiveERC20FailedAirdropPayloadFromOutOfGas() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(nitroAssetForwarder), amount); // amount nitroAssetForwarder receives

        // airdrop all the weth to two addresses
        address user1 = address(0x4203);
        address user2 = address(0x4204);
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        nitroAssetForwarder.handleMessage{gas: 120000}(
            address(usdc),
            amount,
            abi.encode(
                address(user), // to
                "", // swap data
                abi.encode(
                    ISushiXSwapV2Adapter.PayloadData({
                        target: address(airdropExecutor),
                        gasLimit: 200000,
                        targetData: abi.encode(
                            AirdropPayloadExecutor.AirdropPayloadParams({
                                token: address(usdc),
                                recipients: recipients
                            })
                        )
                    })
                ) // payloadData
            )
        );

        assertEq(
            usdc.balanceOf(address(nitroAssetForwarder)),
            0,
            "nitroAssetForwarder should have 0 usdc"
        );
        assertEq(
            usdc.balanceOf(address(routerNitroAdapter)),
            0,
            "routerNitroAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should all usdc");
        assertEq(
            usdc.balanceOf(user1),
            0,
            "user1 should have 0 usdc from airdrop"
        );
        assertEq(
            usdc.balanceOf(user2),
            0,
            "user2 should have 0 usdc from airdrop"
        );
    }
}
