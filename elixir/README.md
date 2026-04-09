# Elixir Harness

This directory contains the primary host-side test harness for the
`pthread_workqueue` project.

## Current commands

Run formatting:

```sh
make -C elixir format
```

Run the ExUnit suite:

```sh
make -C elixir test
```

## OTP note for this host

The installed Elixir was built against Erlang/OTP 28 while the default `erl`
on this machine is OTP 26.

The local wrapper commands in `Makefile` solve this by preferring:

```text
/usr/local/lib/erlang28/bin
```

That keeps the workaround local to the harness instead of modifying the host
globally.
