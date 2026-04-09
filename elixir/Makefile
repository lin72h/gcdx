OTP28_BIN ?= /usr/local/lib/erlang28/bin
OTP28_PATH = $(OTP28_BIN):$$PATH

.PHONY: format test

format:
	env PATH="$(OTP28_PATH)" mix format

test:
	env PATH="$(OTP28_PATH)" mix test
