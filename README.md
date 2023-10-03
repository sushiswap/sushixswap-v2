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

[0x09938716c4a086a4ebfe10377fdad96f32541303](https://etherscan.io/address/0x09938716c4a086a4ebfe10377fdad96f32541303)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://etherscan.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>BSC</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://bscscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x09938716c4a086a4ebfe10377fdad96f32541303](https://bscscan.com/address/0x09938716c4a086a4ebfe10377fdad96f32541303)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://bscscan.com/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Avalanche</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://snowtrace.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x09938716c4a086a4ebfe10377fdad96f32541303](https://snowtrace.io/address/0x09938716c4a086a4ebfe10377fdad96f32541303)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://snowtrace.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Polygon</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://polygonscan.com/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x02a480a258361c9Bc3eaacBd6473364C67adCD3a](https://polygonscan.com/address/0x02a480a258361c9Bc3eaacBd6473364C67adCD3a)
</td><td>

[0x01f27998B1fc39b5280BcBe2a24043f9dbDFc305](https://polygonscan.com/address/0x01f27998B1fc39b5280BcBe2a24043f9dbDFc305)
</td></tr>
<tr>
<td>Arbitrum</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://arbiscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x09938716c4a086a4ebfe10377fdad96f32541303](https://arbiscan.io/address/0x09938716c4a086a4ebfe10377fdad96f32541303)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://arbiscan.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Optimism</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://optimistic.etherscan.io/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x09938716c4a086a4ebfe10377fdad96f32541303](https://optimistic.etherscan.io/address/0x09938716c4a086a4ebfe10377fdad96f32541303)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://optimistic.etherscan.io/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
<tr>
<td>Base</td>
<td>

[0x804b526e5bf4349819fe2db65349d0825870f8ee](https://basescan.org/address/0x804b526e5bf4349819fe2db65349d0825870f8ee)
</td><td>

[0x09938716c4a086a4ebfe10377fdad96f32541303](https://basescan.org/address/0x09938716c4a086a4ebfe10377fdad96f32541303)
</td><td>

[0x02a480a258361c9bc3eaacbd6473364c67adcd3a](https://basescan.org/address/0x02a480a258361c9bc3eaacbd6473364c67adcd3a)
</td></tr>
</table>


## License

GPL-3.0-or-later
