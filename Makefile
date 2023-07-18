-include .env

build:
	forge build
rebuild:
	clean build
install: init
init:
	git submodule update --init --recursive
	forge install
test:
	forge test -vv
test-gas-report:
	forge test -vv --gas-report
trace:
	forge test -vvvv
coverage:
	forge coverage
coverage-info:
	forge coverage --report debug


deploy:
	forge script ./script/DeploySushiXSwapV2.s.sol --broadcast --slow --optimize --optimizer-runs 999999 --names --verify --rpc-url ${RPC_URL} --chain ${CHAIN_ID} --etherscan-api-key ${ETHERSCAN_API_KEY}

verify:
	forge verify-contract 0x94dc339CA423D41B74f8eB4bbC68e5D6B7254b10 SushiXSwapV2 --chain-id 42161 --etherscan-api-key ${ETHERSCAN_API_KEY} --num-of-optimizations 999999 --watch

.PHONY: test