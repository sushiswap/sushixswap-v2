// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {ConnextAdapter} from "../../src/adapters/ConnextAdapter.sol";
import {AirdropPayloadExecutor} from "../../src/payload-executors/AirdropPayloadExecutor.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

contract ConnextAdapterXReceiveTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    ConnextAdapter public connextAdapter;
    AirdropPayloadExecutor public airdropExecutor;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    address public connext;

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

        connext = constants.getAddress("mainnet.connext");

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

        // deploy payload executors
        airdropExecutor = new AirdropPayloadExecutor();

        vm.stopPrank();
    }

    function test_ReceiveERC20SwapToERC20() public {}

    function test_ReceiveWethUnwrapIntoNativeWithRP() public {
    }

    function test_ReceiveExtraERC20SwapToERC20UserReceivesExtra() public {}

    function test_ReceiveUSDTSwapToERC20() public {}

    function test_ReceiveERC20AndNativeSwapToERC20ReturnDust() public {}

    function test_ReceiveERC20SwapToNative() public {}

    function test_ReceiveERC20NotEnoughGasForSwap() public {}

    function test_ReceiveUSDTNotEnoughGasForSwap() public {}

    function test_ReceiveERC20AndNativeNotEnoughGasForSwap() public {}

    function test_ReceiveERC20EnoughForGasNoSwapOrPayloadData() public {}

    function test_ReceiveERC20FailedSwap() public {}

    function test_ReceiveUSDCAndNativeFailedSwapMinimumGasSent() public {}

    function test_ReceiveERC20FailedSwapFromOutOfGas() public {}

    function test_ReceiveERC20FailedSwapSlippageCheck() public {}

    function test_ReceiveERC20SwapToERC20AirdropERC20FromPayload() public {}

    function test_ReceiveERC20SwapToERC20FailedAirdropFromPayload() public {}

    function test_ReceiveERC20AirdropFromPayload() public {}

    function test_ReceiveERC20FailedAirdropFromPayload() public {}

    function test_ReceiveERC20FailedAirdropPayloadFromOutOfGas() public {}
}
