-include .env


deploy:
	forge script ./script/DeploySushiXSwapV2.s.sol --broadcast --slow --optimize --optimizer-runs 999999 --names --verify --rpc-url ${RPC_URL} --chain ${CHAIN_ID} --etherscan-api-key ${ETHERSCAN_API_KEY}

verify:
	forge verify-contract 0xb28d0d2346f77623fb8a859b46128b1a2b6f6bc2 SushiXSwapV2 --chain-id 42161 --etherscan-api-key PEJ1SI5PEGFMT2G8MKSMC9ND43CURSFQHJ --num-of-optimizations 999999 --watch