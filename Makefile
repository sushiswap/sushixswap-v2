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

.PHONY: test