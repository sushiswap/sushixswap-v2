// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "../interfaces/ISushiXSwapV2Adapter.sol";
import "../interfaces/IRouteProcessor.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {INitroAssetForwarder} from "../interfaces/nitro/INitroAssetForwarder.sol";
import {INitroMessageHandler} from "../interfaces/nitro/INitroMessageHandler.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AddressToString} from "../utils/AddressString.sol";
import {Bytes32ToString} from "../utils/Bytes32String.sol";

contract RouterNitroAdapter is ISushiXSwapV2Adapter, INitroMessageHandler {
    using SafeERC20 for IERC20;

    IRouteProcessor public immutable rp;
    IWETH public immutable weth;
    INitroAssetForwarder public immutable nitroAssetForwarder;

    address public constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant PARTNER_ID = 0;

    struct NitroBridgeParams {
        bytes32 destChainIdBytes; // destination chain identifier
        bytes destinationAddress; // destination address for handleMessage call
        address srcToken; // token getting bridged
        uint256 amount; // amount to bridge
        uint256 destAmount; // min amount of destination token
        bytes destToken; // destination token address in bytes
        address refundRecipient; // address of refund recipient on src chain if transaction expires on bridge.
        address to; // address for fallback transfers on handleMessage call
    }

    error RpSentNativeIn();
    error OnlyNitroAssetForwarder();

    constructor(
        address _nitroAssetForwarder,
        address _rp,
        address _weth
    )  {
        nitroAssetForwarder = INitroAssetForwarder(_nitroAssetForwarder);
        rp = IRouteProcessor(_rp);
        weth = IWETH(_weth);
    }


    function getChainIdBytes(
        string memory _chainId
    ) public pure returns (bytes32) {
        bytes32 chainIdBytes32;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainIdBytes32 := mload(add(_chainId, 32))
        }

        return chainIdBytes32;
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function swap(
        uint256 _amountBridged,
        bytes calldata _swapData,
        address,
        bytes calldata _payloadData
    ) external payable override {
        IRouteProcessor.RouteProcessorData memory rpd = abi.decode(
            _swapData,
            (IRouteProcessor.RouteProcessorData)
        );

        // send tokens to RP
        IERC20(rpd.tokenIn).safeTransfer(address(rp), _amountBridged);

        rp.processRoute(
            rpd.tokenIn,
            _amountBridged,
            rpd.tokenOut,
            rpd.amountOutMin,
            rpd.to,
            rpd.route
        );

        // tokens should be sent via rp
        if (_payloadData.length > 0) {
            PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
            try
                IPayloadExecutor(pd.target).onPayloadReceive{gas: pd.gasLimit}(
                    pd.targetData
                )
            {} catch (bytes memory) {
                revert();
            }
        }
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function executePayload(
        uint256 _amountBridged,
        bytes calldata _payloadData,
        address _token
    ) external payable override {
        PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
        IERC20(_token).safeTransfer(pd.target, _amountBridged);
        IPayloadExecutor(pd.target).onPayloadReceive{gas: pd.gasLimit}(
            pd.targetData
        );
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function adapterBridge(
        bytes calldata _adapterData,
        address,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) external payable override {
        NitroBridgeParams memory params = abi.decode(
            _adapterData,
            (NitroBridgeParams)
        );
        
        uint256 value = 0;

        if (params.srcToken == NATIVE_ADDRESS) {
            if (params.amount == 0) 
                params.amount  = address(this).balance;
            value = params.amount;
        } else {
            if (params.amount == 0)
                params.amount = IERC20(params.srcToken).balanceOf(address(this));

            IERC20(params.srcToken).forceApprove(
                address(nitroAssetForwarder),
                params.amount
            );
        }
        
        // build payload from _swapData and _payloadData
        bytes memory payload = abi.encode(params.to, _swapData, _payloadData);
    
        INitroAssetForwarder.DepositData memory depositData = INitroAssetForwarder.DepositData({
            partnerId: PARTNER_ID,
            amount: params.amount,
            destAmount: params.destAmount,
            srcToken: params.srcToken,
            refundRecipient: params.refundRecipient,
            destChainIdBytes: params.destChainIdBytes
        });
        
        // send token and message w/payload to the nitro asset forwarder contract
        nitroAssetForwarder.iDepositMessage{value: value}(depositData, params.destToken, params.destinationAddress, payload);
    }

    /// @inheritdoc INitroMessageHandler
    function handleMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external {
        uint256 gasLeft = gasleft();

        if (msg.sender != address(nitroAssetForwarder)) revert OnlyNitroAssetForwarder();

        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(message, (address, bytes, bytes));

        uint256 reserveGas = 100000;

        if (gasLeft < reserveGas) {
            if (tokenSent != NATIVE_ADDRESS)
                IERC20(tokenSent).safeTransfer(to, amount);

            /// @dev transfer any native token
            // shouldn"t actually have native in here but we return if it does come in
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasLeft - reserveGas;

        if (_swapData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
                    amount,
                    _swapData,
                    tokenSent,
                    _payloadData
                )
            {} catch (bytes memory) {}
        } else if (_payloadData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).executePayload{gas: limit}(
                    amount,
                    _payloadData,
                    tokenSent
                )
            {} catch (bytes memory) {}
        }

        uint256 tokenBalance = IERC20(tokenSent).balanceOf(address(this));
        if (tokenBalance > 0)
            IERC20(tokenSent).safeTransfer(to, tokenBalance);

        uint256 nativeBalance = address(this).balance;
        /// @dev transfer any native token received as dust to the to address
        if (nativeBalance > 0)
            to.call{value: nativeBalance}("");
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function sendMessage(bytes calldata _adapterData) external pure override {
        (_adapterData);
        revert();
    }

    receive() external payable {}
}
