// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {StargateAdapter} from "../../src/adapters/StargateAdapter.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {ISushiXSwapV2Adapter} from "../../src/interfaces/ISushiXSwapV2Adapter.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IStargateFeeLibrary} from "../../src/interfaces/stargate/IStargateFeeLibrary.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {StdUtils} from "forge-std/StdUtils.sol";

contract StargateAdapterReceivesTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    StargateAdapter public stargateAdapter;
    AirdropPayloadExecutor public airdropExecutor;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IStargateFeeLibrary public stargateFeeLibrary;
    address public stargateRouter;
    address public stargateUSDCPoolAddress;
    address public stargateETHPoolAddress;

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

        stargateFeeLibrary = IStargateFeeLibrary(
            constants.getAddress("mainnet.stargateFeeLibrary")
        );
        stargateRouter = constants.getAddress("mainnet.stargateRouter");
        stargateUSDCPoolAddress = constants.getAddress(
            "mainnet.stargateUSDCPool"
        );
        stargateETHPoolAddress = constants.getAddress(
            "mainnet.stargateETHPool"
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

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_RevertWhen_ReceivedCallFromNonStargateRouter() public {
        vm.prank(owner);
        vm.expectRevert();
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            address(usdc),
            1000000,
            ""
        );
    }

    // uint32 keeps max amount to ~4294 usdc
    function test_FuzzReceiveERC20AndSwapToERC20(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory payload = abi.encode(
            address(user), // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        stargateAdapter.sgReceive(0, "", 0, address(usdc), amount, payload);

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
    }

    // uint64 keeps max amount to ~18 eth
    function test_FuzzReceiveNativeAndSwapToERC20(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        vm.deal(stargateRouter, amount); // amount for sgReceive

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory payload = abi.encode(
            address(user), // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: amount}("");
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        stargateAdapter.sgReceive(
            0,
            "",
            0,
            constants.getAddress("mainnet.sgeth"),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
        assertEq(
            weth.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, 0, "user should have 0 eth");
    }

    function test_FuzzReceiveERC20AndDustSwaptoERC20(
        uint32 amount,
        uint64 dustAmount
    ) public {
        vm.assume(amount > 1000000); // > 1 usdc
        vm.assume(dustAmount > 0.001 ether);

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives
        vm.deal(stargateRouter, dustAmount); // dust for sgReceive

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory payload = abi.encode(
            address(user), // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: dustAmount}("");
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        stargateAdapter.sgReceive(0, "", 0, address(usdc), amount, payload);

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 weth"
        );
        assertGt(weth.balanceOf(user), 0, "user should have > 0 weth");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, dustAmount, "user should have all the dust");
    }

    function test_FuzzReceiveNativeAndDustSwaptoERC20(
        uint64 amount,
        uint64 dustAmount
    ) public {
        amount = uint64(bound(amount, 0.1 ether, 10 ether));
        dustAmount = uint64(bound(dustAmount, 0.001 ether, 0.1 ether));

        vm.deal(stargateRouter, amount + dustAmount); // amount for sgReceive

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory payload = abi.encode(
            address(user), // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: (amount + dustAmount)}("");
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        stargateAdapter.sgReceive(
            0,
            "",
            0,
            constants.getAddress("mainnet.sgeth"),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
        assertEq(
            weth.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(
            user.balance,
            dustAmount,
            "user should have dustAmount or greater of eth"
        );
    }

    // uint32 keeps max amount to ~4294 usdc
    function test_FuzzReceiveERC20NotEnoughGasForSwap(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive usdc and attempt swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        stargateAdapter.sgReceive{gas: 90000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(
            weth.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_FuzzReceiveNativeNotEnoughGasForSwap(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        vm.deal(stargateRouter, amount); // amount for sgReceive

        // receive native (sgETH) and attempt swap to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: amount}("");
        stargateAdapter.sgReceive{gas: 90000}(
            0,
            "",
            0,
            constants.getAddress("mainnet.sgeth"),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, amount, "user should have all the eth");
    }

    function test_FuzzReceiveERC20AndDustNotEnoughForGasNoSwapData(
        uint32 amount,
        uint64 dustAmount
    ) public {
        vm.assume(amount > 1000000); // > 1 usdc
        vm.assume(dustAmount > 0.001 ether);

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives
        vm.deal(stargateRouter, dustAmount); // dust for sgReceive

        // receive usdc & dust and attempt to swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: dustAmount}("");
        stargateAdapter.sgReceive{gas: 90000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, dustAmount, "user should have all the dust");
    }

    function test_FuzzReceiveERC20EnoughForGasNoSwapData(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // no swap data, payload empty
        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
    }

    function test_FuzzReceiveNativeEnoughForGasNoSwapData(
        uint64 amount
    ) public {
        vm.assume(amount > 0.1 ether);

        vm.deal(stargateRouter, amount); // amount for sgReceive

        // no swap data, payload empty
        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: amount}("");
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            constants.getAddress("mainnet.sgeth"),
            amount,
            payload
        );

        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, amount, "user should have all the eth");
    }

    function test_FuzzReceiveERC20AndDustEnoughForGasNoSwapData(
        uint32 amount,
        uint64 dustAmount
    ) public {
        vm.assume(amount > 1000000); // > 1 usdc
        vm.assume(dustAmount > 0.1 ether);

        vm.deal(stargateRouter, dustAmount); // dust for sgReceive
        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // no swap data, payload empty
        bytes memory payload = abi.encode(
            user, // to
            "", // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: dustAmount}("");
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, dustAmount, "user should have all the dust");
    }

    function test_FuzzReceiveERC20FailedSwap(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive usdc and attempt swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_FuzzReceiveERC20FailedSwapFromOutOfGas(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive usdc and attempt swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        // attempt swap from usdc to weth
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        stargateAdapter.sgReceive{gas: 100005}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_FuzzReceiveERC20AndDustFailedSwap(
        uint32 amount,
        uint64 dustAmount
    ) public {
        vm.assume(amount > 1000000); // > 1 usdc
        vm.assume(dustAmount > 0.1 ether);

        vm.deal(stargateRouter, dustAmount); // dust for sgReceive
        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive usdc and attempt swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(usdc),
            address(weth),
            500,
            user
        );

        // switched tokenIn to weth, and tokenOut to usdc - should fail now on swap
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: dustAmount}("");
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, dustAmount, "user should have all the dust");
    }

    function test_FuzzReceiveNativeFailedSwap(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        vm.deal(stargateRouter, amount); // amount for sgReceive

        // receive native (sgETH) and attempt swap to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(weth),
            address(usdc),
            500,
            user
        );

        // switched tokenIn to usdc, and tokenOut to weth - should fail now on swap
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

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: amount}("");
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            constants.getAddress("mainnet.sgeth"),
            amount,
            payload
        );

        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, amount, "user should have all the eth");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_FuzzReceiveERC20FailSwapSlippageCheck(uint32 amount) public {
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive usdc and attempt swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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
                amountOutMin: type(uint256).max, // abnormally high amountOutMin
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            address(usdc),
            amount,
            payload
        );

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), amount, "user should have all the usdc");
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
    }

    function test_FuzzReceiveNativeFailSwapSlippageCheck(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        vm.deal(stargateRouter, amount); // amount for sgReceive

        // receive native (sgETH) and attempt swap to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
            false,
            address(weth),
            address(usdc),
            500,
            user
        );

        // attempt to swap weth to usdc with max amount of amountOutMin
        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: address(weth),
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: type(uint256).max,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        bytes memory payload = abi.encode(
            user, // to
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.startPrank(constants.getAddress("mainnet.stargateRouter"));
        address(stargateAdapter).call{value: amount}("");
        stargateAdapter.sgReceive{gas: 200000}(
            0,
            "",
            0,
            constants.getAddress("mainnet.sgeth"),
            amount,
            payload
        );

        assertEq(
            address(stargateAdapter).balance,
            0,
            "stargateAdapter should have 0 eth"
        );
        assertEq(user.balance, amount, "user should have all the eth");
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
    }

    function test_ReceiveERC20AndSwapToERC20AndAirdropERC20FromPayload() public {
        uint32 amount = 1000001;
        vm.assume(amount > 1000000); // > 1 usdc

        deal(address(usdc), address(stargateAdapter), amount); // amount adapter receives

        // receive 1 usdc and swap to weth
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false,
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

        vm.prank(constants.getAddress("mainnet.stargateRouter"));
        // auto sends enough gas, so no need to calculate gasNeeded & send here
        stargateAdapter.sgReceive(0, "", 0, address(usdc), amount, abi.encode(
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
            ), // rpd data
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
        ));

        assertEq(
            usdc.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 usdc"
        );
        assertEq(usdc.balanceOf(user), 0, "user should have 0 usdc");
        assertEq(
            weth.balanceOf(address(stargateAdapter)),
            0,
            "stargateAdapter should have 0 weth"
        );
        assertEq(weth.balanceOf(user), 0, "user should have 0 weth");
        assertGt(weth.balanceOf(user1), 0, "user1 should have > 0 weth from airdrop");
        assertGt(weth.balanceOf(user2), 0, "user2 should have > 0 weth from airdrop");
    }

    

    
}
