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
	forge test -vv --match-contract CCTPBridgeTest
test-gas-report:
	forge test -vv --gas-report
trace:
	forge test -vvvv
coverage:
	forge coverage
coverage-info:
	forge coverage --report debug

.PHONY: test