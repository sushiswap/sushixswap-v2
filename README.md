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
<th>SquidAdapter</th>
</tr>
<tr>
<td>Ethereum</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://etherscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xD408a20f1213286fB3158a2bfBf5bFfAca8bF269](https://etherscan.io/address/0xD408a20f1213286fB3158a2bfBf5bFfAca8bF269)
</td><td>

[0xFF51a7C624Eb866917102707F3dA8bFb99Db8692](https://etherscan.io/address/0xFF51a7C624Eb866917102707F3dA8bFb99Db8692)
</td></tr>
<tr>
<td>BSC</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://bscscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xFF51a7C624Eb866917102707F3dA8bFb99Db8692](https://bscscan.com/address/0xFF51a7C624Eb866917102707F3dA8bFb99Db8692)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://bscscan.com/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td></tr>
<tr>
<td>Avalanche</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://snowtrace.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xFF51a7C624Eb866917102707F3dA8bFb99Db8692](https://snowtrace.io/address/0xFF51a7C624Eb866917102707F3dA8bFb99Db8692)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://snowtrace.io/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td></tr>
<tr>
<td>Polygon</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://polygonscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x1719DEf1BF8422a777f2442bcE704AC4Fb20c7f0](https://polygonscan.com/address/0x1719DEf1BF8422a777f2442bcE704AC4Fb20c7f0)
</td><td>

[0x1B4eb3e90dA47ff898d2cda40B5750721886E850](https://polygonscan.com/address/0x1B4eb3e90dA47ff898d2cda40B5750721886E850)
</td></tr>
<tr>
<td>Arbitrum</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://arbiscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xFF51a7C624Eb866917102707F3dA8bFb99Db8692](https://arbiscan.io/address/0xFF51a7C624Eb866917102707F3dA8bFb99Db8692)
</td><td>

[0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6](https://arbiscan.io/address/0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6)
</td></tr>
<tr>
<td>Optimism</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://optimistic.etherscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xA62eC622DbA415Aa94110739B1f951B1202Cf322](https://optimistic.etherscan.io/address/0xA62eC622DbA415Aa94110739B1f951B1202Cf322)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://optimistic.etherscan.io/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td></tr>
<tr>
<td>Base</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://basescan.org/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xD408a20f1213286fB3158a2bfBf5bFfAca8bF269](https://basescan.org/address/0xD408a20f1213286fB3158a2bfBf5bFfAca8bF269)
</td><td>

[0xFF51a7C624Eb866917102707F3dA8bFb99Db8692](https://basescan.org/address/0xFF51a7C624Eb866917102707F3dA8bFb99Db8692)
</td></tr>
<tr>
<td>Fantom</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://ftmscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://ftmscan.com/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td><td>

[0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6](https://ftmscan.com/address/0x454714482cA38fBBcE7fC76D96Ba1CE2028A4fF6)
</td></tr>
<tr>
<td>Linea</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://lineascan.build/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0xA62eC622DbA415Aa94110739B1f951B1202Cf322](https://lineascan.build/address/0xA62eC622DbA415Aa94110739B1f951B1202Cf322)
</td><td>

[0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0](https://lineascan.build/address/0xbF3B71decBCEFABB3210B9D8f18eC22e0556f5F0)
</td></tr>
<tr>
<td>Kava</td>
<td>

[0xD5607d184b1D6ecbA94A07c217497FE9346010D9](https://kavascan.com/address/0xD5607d184b1D6ecbA94A07c217497FE9346010D9)
</td><td>

[0x891f29AA86aB4E1F4798795378B5E763aA232EF6](https://kavascan.com/address/0x891f29AA86aB4E1F4798795378B5E763aA232EF6)
</td><td>

[0xEfb2b93B2a039A227459AAD0572a019Aba8eA69d](https://kavascan.com/address/0xEfb2b93B2a039A227459AAD0572a019Aba8eA69d)
</td></tr>
<tr>
<td>Metis</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://andromeda-explorer.metis.io/address/0x804b526e5bF4349819fe2Db65349d0825870F8Ee)
</td><td>

[0xDf1cfEc0DCF05bf647FbfbE12ea550Baa102E195](https://andromeda-explorer.metis.io/address/0xDf1cfEc0DCF05bf647FbfbE12ea550Baa102E195)
</td><td>
</td></tr>
<tr>
<td>Moonbeam</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://moonscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>
</td><td>

[0x02a480a258361c9Bc3eaacBd6473364C67adCD3a](https://moonscan.io/address/0x02a480a258361c9Bc3eaacBd6473364C67adCD3a)
</td></tr>
<tr>
<td>CELO</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://celoscan.io/address/0x804b526e5bF4349819fe2Db65349d0825870F8Ee)
</td><td>
</td><td>

[0x02a480a258361c9Bc3eaacBd6473364C67adCD3a](https://celoscan.io/address/0x02a480a258361c9Bc3eaacBd6473364C67adCD3a)
</td></tr>
<tr>
<td>Scroll</td>
<td>

[0x804b526e5bF4349819fe2Db65349d0825870F8Ee](https://scrollscan.com/address/0x804b526e5bF4349819fe2Db65349d0825870F8Ee)
</td><td>
</td><td>

[0x02a480a258361c9Bc3eaacBd6473364C67adCD3a](https://scrollscan.com/address/0x02a480a258361c9Bc3eaacBd6473364C67adCD3a)
</td></tr>
</table>


## License

GPL-3.0-or-later
