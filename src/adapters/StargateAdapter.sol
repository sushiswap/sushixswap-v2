// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IRouteProcessor.sol";
import "../interfaces/IWETH.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/stargate/IStargateRouter.sol";
import "../interfaces/stargate/IStargateReceiver.sol";
import "../interfaces/stargate/IStargateWidget.sol";
import "../interfaces/stargate/IStargateEthVault.sol";

contract StargateAdapter is ISushiXSwapV2Adapter {
    using SafeERC20 for IERC20;

    IStargateRouter public immutable stargateRouter;
    IStargateWidget public immutable stargateWidget;
    address public immutable sgeth;
    IRouteProcessor public immutable rp;
    IWETH public immutable weth;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct StargateTeleportParams {
        uint16 dstChainId; // stargate dst chain id
        address token; // token getting bridged
        uint256 srcPoolId; // stargate src pool id
        uint256 dstPoolId; // stargate dst pool id
        uint256 amount; // amount to bridge
        uint256 amountMin; // amount to bridge minimum
        uint256 dustAmount; // native token to be received on dst chain
        address receiver;
        address to;
        uint256 gas; // extra gas to be sent for dst chain operations
    }

    error InsufficientGas();
    error NotStargateRouter();

    constructor(
        address _stargateRouter,
        address _stargateWidget,
        address _sgeth,
        address _rp,
        address _weth
    ) {
        stargateRouter = IStargateRouter(_stargateRouter);
        stargateWidget = IStargateWidget(_stargateWidget);
        sgeth = _sgeth;
        rp = IRouteProcessor(_rp);
        weth = IWETH(_weth);
    }

    function swap(
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external override {
        IRouteProcessor.RouteProcessorData memory rpd = abi.decode(
            _swapData,
            (IRouteProcessor.RouteProcessorData)
        );
        if (_token == sgeth) {
            //todo: need to figure out if sgETH is token does it come in as native?
            weth.deposit{value: rpd.amountIn}();
        }
        // increase token approval to RP
        IERC20(rpd.tokenIn).safeIncreaseAllowance(address(rp), rpd.amountIn);

        rp.processRoute(
            rpd.tokenIn,
            rpd.amountIn,
            rpd.tokenOut,
            rpd.amountOutMin,
            rpd.to,
            rpd.route
        );

        // tokens should be sent via rp
        if (_payloadData.length > 0) {
            PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
            try
                IPayloadExecutor(pd.target).onPayloadReceive(pd.targetData)
            {} catch (bytes memory) {
                revert();
            }
        }
    }

    /// @notice Get the fees to be paid in native token for the swap
    /// @param _dstChainId stargate dst chainId
    /// @param _functionType stargate Function type 1 for swap.
    /// See more at https://stargateprotocol.gitbook.io/stargate/developers/function-types
    /// @param _receiver receiver on the dst chain
    /// @param _gas extra gas being sent
    /// @param _dustAmount dust amount to be received at the dst chain
    /// @param _payload payload being sent at the dst chain
    function getFee(
        uint16 _dstChainId,
        uint8 _functionType,
        address _receiver,
        uint256 _gas,
        uint256 _dustAmount,
        bytes memory _payload
    ) external view returns (uint256 a, uint256 b) {
        (a, b) = stargateRouter.quoteLayerZeroFee(
            _dstChainId,
            _functionType,
            abi.encodePacked(_receiver),
            abi.encode(_payload),
            IStargateRouter.lzTxObj(
                _gas,
                _dustAmount,
                abi.encodePacked(_receiver)
            )
        );
    }

    function adapterBridge(
        bytes calldata _adapterData,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) external payable override {
        StargateTeleportParams memory params = abi.decode(
            _adapterData,
            (StargateTeleportParams)
        );

        // todo: can prob remove this native case, and do the wrap in the xSwap contract
        if (params.token == NATIVE_ADDRESS) {
            // todo: need to figure out this edge case:
                // swapToNativeAndBridge
                // rp will swap and send native to this adapter
                // and then the amount for bridge & value of eth/gas to forward
                // gets mixed up / the amount to bridge is unknown from here
                
                // thinking maybe better to swap to weth send to adapter
                // then if weth unwrap to eth and wrap to sgETH
                // or do we do that in sushiXswap.swap and then check balance for amount
                // we do have weth in here so we could if weth address and amount = 0 check balance for amount
            IStargateEthVault(sgeth).deposit{value: params.amount}();
            params.token = sgeth;
        } else if (params.token == address(weth)) {
            params.amount = weth.balanceOf(address(this));
            weth.withdraw(params.amount);
            IStargateEthVault(sgeth).deposit{value: params.amount}();
            params.token = sgeth;    
        }

        IERC20(params.token).safeApprove(
            address(stargateRouter),
            params.amount != 0
                ? params.amount
                : IERC20(params.token).balanceOf(address(this))
        );

        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            /// @dev dst gas should be more than 100k
            if (params.gas < 100000) revert InsufficientGas();
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        stargateRouter.swap{value: address(this).balance}(
            params.dstChainId,
            params.srcPoolId,
            params.dstPoolId,
            payable(tx.origin), // refund address
            params.amount != 0
                ? params.amount
                : IERC20(params.token).balanceOf(address(this)),
            params.amountMin,
            IStargateRouter.lzTxObj(
                params.gas,
                params.dustAmount,
                abi.encodePacked(params.receiver)
            ),
            abi.encodePacked(params.receiver),
            payload
        );

        stargateWidget.partnerSwap(0x0001);
    }

    /// @notice Receiver function on dst chain
    /// @param _token bridge token received
    /// @param amountLD amount received
    /// @param payload ABI-Encoded data received from src chain
    function sgReceive(
        uint16,
        bytes memory,
        uint256,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external payable {
        if (msg.sender != address(stargateRouter)) revert NotStargateRouter();

        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(payload, (address, bytes, bytes));

        uint256 reserveGas = 100000;
        bool failed;

        if (gasleft() < reserveGas) {
            if (_token != sgeth) {
                IERC20(_token).safeTransfer(to, amountLD);
            }
            // todo: I think we need something handle sgETH receives

            /// @dev transfer any native token received as dust to the to address
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            failed = true;
            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasleft() - reserveGas;

        if (_swapData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
                    _swapData,
                    _token,
                    _payloadData
                )
            {} catch (bytes memory) {
                if (_token != sgeth) {
                    IERC20(_token).safeTransfer(to, amountLD);
                }
                failed = true;
            }
        }

        /// @dev transfer any native token received as dust to the to address
        if (address(this).balance > 0)
            to.call{value: (address(this).balance)}("");
    }

    function sendMessage(bytes calldata _adapterData) external {
        (_adapterData);
        revert();
    }

    receive() external payable {}
}
