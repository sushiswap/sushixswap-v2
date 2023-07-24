// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.10;

interface ITokenMessenger {
    // this event will be emitted when `depositForBurn` function is called.
    event MessageSent(bytes message);
 
    /**
    * @param _amount amount of tokens to burn
    * @param _destinationDomain destination domain
    * @param _mintRecipient address of mint recipient on destination domain
    * @param _burnToken address of contract to burn deposited tokens, on local
    domain
    * @return _nonce uint64, unique nonce for each burn
    */
    function depositForBurn(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken
    ) external returns (uint64 _nonce);
}