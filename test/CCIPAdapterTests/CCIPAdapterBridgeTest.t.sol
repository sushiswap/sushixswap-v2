// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {CCIPAdapter} from "../../src/adapters/CCIPAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

contract CCIPAdapterBridgeTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    CCIPAdapter public ccipAdapter;
    IRouteProcessor public routeProcessor;
    RouteProcessorHelper public routeProcessorHelper;

    IWETH public weth;
    IERC20 public sushi;
    IERC20 public usdc;
    IERC20 public usdt;
    IERC20 public betsToken;

    uint64 op_chainId = 3734403246176062136; // OP
    uint64 base_chainId = 15971525489660198786; // base
    uint64 polygon_chainId = 4051577828743386545; // polygon

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
        betsToken = IERC20(constants.getAddress("mainnet.betsToken"));

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
        ccipAdapter = new CCIPAdapter(
            constants.getAddress("mainnet.ccipRouter"),
            constants.getAddress("mainnet.link"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(ccipAdapter), true);

        vm.stopPrank();
    }

    function test_RevertWhen_SendingMessage() public {
        vm.startPrank(user);
        vm.expectRevert();
        sushiXswap.sendMessage(address(ccipAdapter), "");
    }

    function test_getFee() public {
      //uint256 fees = ccipAdapter.getFee(op_chainId, )
    }

    function test_BridgeERC20() public {
        uint256 amount = 1 ether; // 1 betsToken
        uint64 feeNeeded = 0.1 ether; // eth for gas to pass

        // poll the chainlink fee

        deal(address(betsToken), user, amount);
        vm.deal(user, feeNeeded);

        // basic usdc bridge, mint betsToken on otherside
        vm.startPrank(user);
        betsToken.safeIncreaseAllowance(address(sushiXswap), amount);

        sushiXswap.bridge{value: feeNeeded}(
            ISushiXSwapV2.BridgeParams({
                refId: 0x0000,
                adapter: address(ccipAdapter),
                tokenIn: address(betsToken),
                amountIn: amount,
                to: user,
                adapterData: abi.encode(
                    polygon_chainId, // chainId
                    user,    // receiver 
                    user,    // to
                    address(betsToken), // token
                    amount, // amount
                    150000  // gasLimit
                )
            }),
            user, // _refundAddress
            "", // swap payload
            "" // payload data
        );

        assertEq(
            betsToken.balanceOf(address(ccipAdapter)),
            0,
            "ccipAdapter should have 0 betsToken"
        );
        assertEq(betsToken.balanceOf(user), 0, "user should have 0 betsToken");
    }
}