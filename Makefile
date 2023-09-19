-include .env

build:
	forge build
rebuild:
	clean build
install: init
init:
	git submodule update --init --recursive
	forge install
	cd lib/forge-deploy && cargo build --release && cp target/release/forge-deploy ../../forge-deploy
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
	./forge-deploy gen-deployer
	forge script ./script/DeploySushiXSwapV2.s.sol --broadcast --slow --optimize --optimizer-runs 999999 --names --verify --rpc-url ${RPC_URL} --chain ${CHAIN_ID} --etherscan-api-key ${ETHERSCAN_API_KEY} --private-key ${PRIVATE_KEY}
	./forge-deploy sync
.PHONY: test
