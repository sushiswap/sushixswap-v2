// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {SushiXSwapV2} from "../../src/SushiXSwapV2.sol";
import {CCIPAdapter} from "../../src/adapters/CCIPAdapter.sol";
import {ISushiXSwapV2} from "../../src/interfaces/ISushiXSwapV2.sol";
import {IRouteProcessor} from "../../src/interfaces/IRouteProcessor.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "../../utils/BaseTest.sol";
import "../../utils/RouteProcessorHelper.sol";

import {IOwnerAndAllowListManager} from "./interfaces/IOwnerAndAllowListManager.sol";

contract CCIPAdapterHarness is CCIPAdapter {
  constructor(
    address _router,
    address _link,
    address _rp,
    address _weth
  ) CCIPAdapter(_router, _link, _rp, _weth) {}

  function exposed_ccipReceive(
    Client.Any2EVMMessage memory any2EVMMessage
  ) external {
    _ccipReceive(any2EVMMessage);
  }

  function build_Any2EVMMessage(
      address sender,
      address token,
      uint256 amount,
      bytes calldata mockPayload
    ) external returns (Client.Any2EVMMessage memory any2EVMMessage){
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
          token: token,
          amount: amount
        });

        any2EVMMessage = Client.Any2EVMMessage({
          messageId: 0,
          sourceChainSelector: 3734403246176062136,
          sender: abi.encode(sender),
          data: mockPayload,
          destTokenAmounts: destTokenAmounts
        });
    }
}

contract CCIPAdapterExecutesTest is BaseTest {
    using SafeERC20 for IERC20;

    SushiXSwapV2 public sushiXswap;
    CCIPAdapter public ccipAdapter;
    CCIPAdapterHarness public ccipAdapterHarness;
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
        ccipAdapterHarness = new CCIPAdapterHarness(
            constants.getAddress("mainnet.ccipRouter"),
            constants.getAddress("mainnet.link"),
            constants.getAddress("mainnet.routeProcessor"),
            constants.getAddress("mainnet.weth")
        );
        sushiXswap.updateAdapterStatus(address(ccipAdapter), true);

        vm.stopPrank();

        // turn off allowlist on Evm2EvmOnRamp
        IOwnerAndAllowListManager onRamp = IOwnerAndAllowListManager(
            constants.getAddress("mainnet.evm2evmOnRamp")
        );
        IOwnerAndAllowListManager burnMintPool = IOwnerAndAllowListManager(
            constants.getAddress("mainnet.burnMintTokenPool")
        );
        vm.prank(onRamp.owner());
        onRamp.setAllowListEnabled(false);
        vm.prank(burnMintPool.owner());
        address[] memory removeList = new address[](1);
        removeList[0] = address(0x0);
        address[] memory addList = new address[](1);
        addList[0] = address(ccipAdapter);
        burnMintPool.applyAllowListUpdates(removeList, addList);
    }

    function testFuzz_ReceiveERC20SwapToERC20(uint64 amount) public {
      vm.assume(amount > 0.1 ether);

      deal(address(betsToken), address(ccipAdapterHarness), amount);

      // receive 1 betsToken and swap to usdc
      bytes memory computedRoute_dst = routeProcessorHelper.computeRoute(
        true,
        false,
        address(betsToken),
        address(usdc),
        3000,
        user
      );

      IRouteProcessor.RouteProcessorData memory rpd = IRouteProcessor
        .RouteProcessorData({
            tokenIn: address(betsToken),
            amountIn: amount,
            tokenOut: address(usdc),
            amountOutMin: 0,
            to: user,
            route: computedRoute_dst
        });

      bytes memory rpd_encoded = abi.encode(rpd);

      bytes memory mockPayload = abi.encode(
        user, // to
        rpd_encoded, // _swapData
        "" // _payloadData
      );

      Client.Any2EVMMessage memory mockEvmMessage = ccipAdapterHarness.build_Any2EVMMessage(
        address(ccipAdapter),
        address(betsToken),
        amount,
        mockPayload
      );

      ccipAdapterHarness.exposed_ccipReceive(mockEvmMessage);

      assertEq(
        betsToken.balanceOf(address(ccipAdapterHarness)),
        0,
        "ccipAdapterHarness should have 0 betsToken"
      );
      assertEq(
        betsToken.balanceOf(user),
        0,
        "user should have 0 betsToken"
      );
      assertEq(
        usdc.balanceOf(address(ccipAdapterHarness)),
        0,
        "ccipAdapterHarness should have 0 usdc"
      );
      assertGt(usdc.balanceOf(user), 0, "user should have > 0 usdc");
    }

    function test_ReceiveExtraERC20SwapToERC20UserReceivesExtra() public {

    }

    function test_ReceiveERC20AndNativeSwapToERC20ReturnDust() public {

    }

    function test_ReceiveERC20SwapToNative() public {

    }

    function test_ReceiveERC20NotEnoughGasForSwap() public {

    }

    function test_ReceiveERC20AndNativeNotEnoughGasForSwap() public {

    }

    function test_ReceiveERC20EnoughForGasNoSwapOrPayloadData() public {

    }

    function test_ReceiveERC20FailedSwap() public {

    }

    function test_ReceiveERC20FailedSwapFromOutOfGas() public {

    }

    function test_ReceiveERC20FailedSwapSlippageCheck() public {

    }

    function test_ReceiveERC20SwapToERC20AirdropERC20FromPayload() public {

    }

    function test_ReceiveERC20SwapToERC20FailedAirdropFromPayload() public {

    }

    function test_ReceiveERC20AirdropFromPayload() public {

    }

    function test_ReceiveERC20FailedAirdropFromPayload() public {

    }

    function test_ReceiveERC20FailedAirdropPayloadFromOutOfGas() public {

    }
}