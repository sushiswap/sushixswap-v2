// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IOwnerAndAllowListManager {
  function owner() external returns (address);
  function setAllowListEnabled(bool) external;
  function applyAllowListUpdates(address[] calldata, address[] calldata) external;
}