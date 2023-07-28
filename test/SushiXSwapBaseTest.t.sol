// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../src/SushiXSwapV2.sol";
import {StargateAdapter} from "../src/adapters/StargateAdapter.sol";
import {IRouteProcessor} from "../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../utils/BaseTest.sol";
import "../utils/RouteProcessorHelper.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

contract SushiXSwapBaseTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    StargateAdapter public stargateAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    ERC20 public sushi;
    ERC20 public usdc;
    ERC20 public usdt;

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
        usdt = ERC20(constants.getAddress("mainnet.usdt"));

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

    function test_Pause() public {
        vm.prank(owner);
        sushiXswap.pause();

        vm.startPrank(operator);
        sushiXswap.pause();
        // operator, paused, sendMesssage call
        vm.expectRevert();
        sushiXswap.sendMessage(address(stargateAdapter), abi.encode(0x01));

        sushiXswap.resume();

        vm.stopPrank();
    }

    // uint64 keeps it max amount to ~18 weth
    function test_RescueTokens(uint64 amountToRescue) public {
        vm.assume(amountToRescue > 0.1 ether);

        vm.deal(address(sushiXswap), amountToRescue);
        deal(address(sushi), address(sushiXswap), amountToRescue);
        deal(address(weth), address(sushiXswap), amountToRescue);

        // reverts if not owner
        vm.prank(operator);
        vm.expectRevert();
        sushiXswap.rescueTokens(NATIVE_ADDRESS, user);

        vm.startPrank(owner);
        sushiXswap.rescueTokens(NATIVE_ADDRESS, user);
        sushiXswap.rescueTokens(address(sushi), user);
        sushiXswap.rescueTokens(address(weth), user);
        vm.stopPrank();

        assertEq(user.balance, amountToRescue);
        assertEq(sushi.balanceOf(user), amountToRescue);
    }

    function test_OwnerGuard() public {
        vm.startPrank(operator);

        vm.expectRevert();
        sushiXswap.setPrivileged(address(0x01), true);

        vm.expectRevert();
        sushiXswap.updateAdapterStatus(address(0x01), true);

        vm.expectRevert();
        sushiXswap.updateRouteProcessor(address(0x01));

        vm.startPrank(owner);
        sushiXswap.setPrivileged(address(0x01), true);
        sushiXswap.updateAdapterStatus(address(0x01), true);
        sushiXswap.updateRouteProcessor(address(0x01));
    }

    function test_RevertWhenSendMessageStargate() public {
        // sendMessage not implemented for stargate adapter
        vm.expectRevert();
        sushiXswap.sendMessage(address(stargateAdapter), "");
    }

    function testFuzz_SwapERC20ToERC20(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        deal(address(weth), user, amount);

        // basic swap weth to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRoute(
            false, // rpHasToken
            false, // isV2
            address(weth), // tokenIn
            address(usdc), // tokenOut
            500, // fee
            user // to
        );

        vm.startPrank(user);
        ERC20(address(weth)).approve(address(sushiXswap), amount);

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

        sushiXswap.swap(rpd_encoded);

        vm.stopPrank();

        assertEq(weth.balanceOf(user), 0, "weth balance should be 0");
        assertGt(
            usdc.balanceOf(user),
            0,
            "usdc balance should be greater than 0"
        );
    }

    function testFuzz_SwapNativeToERC20(uint64 amount) public {
        vm.assume(amount > 0.1 ether);

        vm.deal(user, amount);

        // swap eth to usdc
        bytes memory computedRoute = routeProcessorHelper.computeRouteNativeIn(
            address(weth), // wrapToken
            false,
            address(usdc),
            500,
            user
        );

        IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
            .RouteProcessorData({
                tokenIn: NATIVE_ADDRESS,
                amountIn: amount,
                tokenOut: address(usdc),
                amountOutMin: 0,
                to: user,
                route: computedRoute
            });

        bytes memory rpd_encoded = abi.encode(rpd);

        vm.prank(user);
        sushiXswap.swap{value: amount}(rpd_encoded);

        assertEq(user.balance, 0, "eth balance should be 0");
        assertGt(
            usdc.balanceOf(user),
            0,
            "usdc balance should be greater than 0"
        );
    }
}
