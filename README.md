# SushiXSwapV2 [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

This repository contains the core smart contracts for SushiXSwapV2.

In-depth documentation is available at [docs.sushi.com](https://docs.sushi.com). [Coming Soon]

## Background

SushiXSwapV2 is a cross-chain enabled protocol that utilizes general message passing through adapters to perform swaps across supported networks. Routing and swap logic is handled with the integration of Sushi's RouteProcessor contract, and additional cross-chain functionality can be implemented through payload-executors.

## Setup

### Install

First, initialize with:

```shell
make init
```

Make a copy of `.env.sample` to `.env` and for tests set the `MAINNET_RPC_URL`.

### Test

To run tests:

```shell
make test
```

## Deployments

<table>
<tr>
<th>Network</th>
<th>SushiXSwapV2</th>
<th>StargateAdapter</th>
<th>AxelarAdapter</th>
</tr>
<tr>
<td>Ethereum</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://etherscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://etherscan.io/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://etherscan.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>BSC</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://bscscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6](https://bscscan.com/address/0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://bscscan.com/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Avalanche</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://snowtrace.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6](https://snowtrace.io/address/0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://snowtrace.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Polygon</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://polygonscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xFF51a7C624Eb866917102707F3dA8bFb99Db8692](https://polygonscan.com/address/0xFF51a7C624Eb866917102707F3dA8bFb99Db8692)
</td><td>

[0x01f27998B1fc39b5280BcBe2a24043f9dbDFc305](https://polygonscan.com/address/0x01f27998B1fc39b5280BcBe2a24043f9dbDFc305)
</td></tr>
<tr>
<td>Arbitrum</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://arbiscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x2ABf469074dc0b54d793850807E6eb5Faf2625b1](https://arbiscan.io/address/0x2ABf469074dc0b54d793850807E6eb5Faf2625b1)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://arbiscan.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Optimism</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://optimistic.etherscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6](https://optimistic.etherscan.io/address/0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://optimistic.etherscan.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Base</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://basescan.org/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://basescan.org/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://basescan.org/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Fantom</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://ftmscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x2ABf469074dc0b54d793850807E6eb5Faf2625b1](https://ftmscan.com/address/0x2ABf469074dc0b54d793850807E6eb5Faf2625b1)
</td><td>

[0x02a480a258361c9Bc3eaacBd6473364C67adCD3a](https://ftmscan.com/address/0x02a480a258361c9Bc3eaacBd6473364C67adCD3a)
</td></tr>
<tr>
<td>Linea</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://lineascan.build/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6](https://lineascan.build/address/0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6)
</td><td>

[0x01f27998B1fc39b5280BcBe2a24043f9dbDFc305](https://lineascan.build/address/0x01f27998b1fc39b5280bcbe2a24043f9dbdfc305)
</td></tr>
<tr>
<td>Kava</td>
<td>

[0xD5607d184b1D6ecbA94A07c217497FE9346010D9](https://kavascan.com/address/0xD5607d184b1D6ecbA94A07c217497FE9346010D9)
</td><td>

[0xDf1cfEc0DCF05bf647FbfbE12ea550Baa102E195](https://kavascan.com/address/0xDf1cfEc0DCF05bf647FbfbE12ea550Baa102E195)
</td><td>

[0x630BE2985674D31920BAbb4F96657960F131E7b1](https://kavascan.com/address/0x630BE2985674D31920BAbb4F96657960F131E7b1)
</td></tr>
<tr>
<td>Metis</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://andromeda-explorer.metis.io/address/0x804b526e5bF4349819fe2Db65349d0825870F8Ee)
</td><td>

[0xA62eC622DbA415Aa94110739B1f951B1202Cf322](https://andromeda-explorer.metis.io/address/0xA62eC622DbA415Aa94110739B1f951B1202Cf322)
</td><td>
</td></tr>
</table>


## License

GPL-3.0-or-later
