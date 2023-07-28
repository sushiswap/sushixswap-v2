// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../interfaces/IPayloadExecutor.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/*
    Basic Airdrop Payload Executor
        Should not be used in production, mainly for testing
        And any additional payloads that are built should have guards
        in place to assure delivery of tokens w/ reverts if correct operations
        doesn't happen. Tokens can potentially get stuck here if received and no revert().
*/
contract AirdropPayloadExecutor is IPayloadExecutor {
    using SafeERC20 for IERC20;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct AirdropPayloadParams {
        address token;
        address[] recipients;
    }

    constructor() {}

    function onPayloadReceive(bytes memory _data) external payable override {
        AirdropPayloadParams memory params = abi.decode(
            _data,
            (AirdropPayloadParams)
        );
        
        uint256 amount;
        if (params.token != NATIVE_ADDRESS)
            amount = IERC20(params.token).balanceOf(address(this));
        else
            amount = address(this).balance;

        if (amount <= 0) {
            revert();
        }

        // prob will have dust from rounding
        uint256 sendAmount = amount / params.recipients.length;

        for (uint256 i = 0; i < params.recipients.length; i++) {
            if (params.token != NATIVE_ADDRESS)
                IERC20(params.token).safeTransfer(params.recipients[i], sendAmount);
            else
                params.recipients[i].call{value: sendAmount}("");
        }
    }
}
