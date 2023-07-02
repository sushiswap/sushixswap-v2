// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

//import "/interfaces/IUniswapV3Factory.sol";
//import "interfaces/IUniswapV3Pool.sol";
//import "interfaces/IUniswapV2Pair.sol";

interface IUniswapV2Factory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV3Factory {
  function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV2Pair {
  function token0() external view returns (address);
  function token1() external view returns (address);
}

interface IUniswapV3Pool {
  function token0() external view returns (address);
  function token1() external view returns (address);
}

contract RouteProcessorHelper {
  IUniswapV2Factory public v2Factory;
  IUniswapV3Factory public v3Factory;
  address public rp;
  address public weth;

  constructor (address _v2Factory, address _v3Factory, address _rp, address _weth) {
    v2Factory = IUniswapV2Factory(_v2Factory);
    v3Factory = IUniswapV3Factory(_v3Factory);
    rp = _rp;
    weth = _weth;
  }

  // only computes routes for v2, and v3 single hop swaps ERC20s
  // mainly to be used for testing purposes
  function computeRoute(bool rpHasToken, bool isV2, address tokenIn, address tokenOut, uint24 fee, address to) public view returns (bytes memory route) {
    address pair;
    address token0;
    address token1;
    uint8 direction;

    if (isV2) {
      pair = v2Factory.getPair(tokenIn, tokenOut);
      token0 = IUniswapV2Pair(pair).token0();
      token1 = IUniswapV2Pair(pair).token1();
    } else {
      pair = v3Factory.getPool(tokenIn, tokenOut, fee);
      token0 = IUniswapV3Pool(pair).token0();
      token1 = IUniswapV3Pool(pair).token1();
    }

    if (token0 == tokenIn) {
      direction = uint8(0x01);
    } else {
      direction = uint8(0x00);
    }

    route = abi.encodePacked(
      uint8(rpHasToken ? 0x01 : 0x02), // 0x01 for pre-transfer to rp & 0x02 for transferFrom msg.sender
      tokenIn,
      uint8(0x01), // always does 1 route
      uint16(0xffff), // always does full amount
      uint8(isV2 ? 0x00 : 0x01), // poolType (0 = v2, 1 = v3)
      pair,
      direction,
      to
    );
  }

  function computeRouteNativeOut(bool rpHasToken, bool isV2, address tokenIn, address tokenOut, uint24 fee, address to) public view returns (bytes memory route) {
    address pair;
    address token0;
    address token1;
    uint8 direction;

    if (isV2) {
      pair = v2Factory.getPair(tokenIn, tokenOut);
      token0 = IUniswapV2Pair(pair).token0();
      token1 = IUniswapV2Pair(pair).token1();
    } else {
      pair = v3Factory.getPool(tokenIn, tokenOut, fee);
      token0 = IUniswapV3Pool(pair).token0();
      token1 = IUniswapV3Pool(pair).token1();
    }

    if (token0 == tokenIn) {
      direction = uint8(0x01);
    } else {
      direction = uint8(0x00);
    }
    
    route = abi.encodePacked(
      uint8(rpHasToken ? 0x01 : 0x02), // 0x01 for pre-transfer to rp & 0x02 for transferFrom msg.sender
      tokenIn,
      uint8(0x01), // always does 1 route
      uint16(0xffff), // always does full amount
      uint8(isV2 ? 0x00 : 0x01), // poolType (0 = v2, 1 = v3)
      pair,
      direction,
      rp,
      uint8(0x01),
      weth,
      uint8(0x01),
      uint16(0xfff),
      uint8(0x02), // wrapNative pool type
      uint8(0x00) // directionAndFake (unwrap weth)
    );

    route = abi.encodePacked(route, to);
  }
}