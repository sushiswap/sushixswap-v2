// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {AxelarAdapter} from "../../src/adapters/AxelarAdapter.sol";
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

contract AxelarAdapterSwapAndBridgeTest is BaseTest {
    SushiXSwapV2 public sushiXswap;
    AxelarAdapter public axelarAdapter;
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
        axelarAdapter = new AxelarAdapter(
            constants.getAddress("mainnet.axelarGateway"),
            constants.getAddress("mainnet.axelarGasService"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(axelarAdapter), true);

        vm.stopPrank();
    }

    function test_ReceiveERC20AndSwapToERC20() public {
        uint32 amount = 1000000; // 1 USDC
        uint64 forwardedGas = 0.1 ether; // eth forwarded

        deal(address(usdc), address(axelarAdapter), amount); // axelar adapter receives USDC

        // receive 1 USDC and swap to weth
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

        bytes memory mockPayload = abi.encode(
            address(user), // refundAddress
            rpd_encoded, // _swapData
            "" // _payloadData
        );

        vm.prank(constants.getAddress(axelarAdapter));
        axelarAdapter._executeWithToken(
          "arbitrum",
          AddressToString.toString(address(axelarAdapter)),
          mockPayload,
          "USDC",
          amount
        );
    }

    function test_ReceiveERC20AndSwapToNative() public {}

    function test_ReceiveERC20NotEnoughGasForSwap() public {}

    function test_ReceiveERC20EnoughForGasNoSwapData() public {}

    function test_ReceiveERC20FailedSwap() public {}

    function test_ReceiveERC20FailedSwapFromOutOfGas() public {}

    function test_ReceiveERC20FailedSwapSlippageCheck() public {}
}
