defmodule TwqTest.EnvTest do
  use ExUnit.Case, async: true

  alias TwqTest.Env

  test "loads deterministic defaults from repo layout" do
    env = Env.load(%{})

    assert String.ends_with?(env.repo_root, "/wip-codex54x")
    assert String.ends_with?(env.project_root, "/wip-codex54x/elixir")
    assert String.ends_with?(env.scripts_dir, "/wip-codex54x/scripts/bhyve")
    assert String.ends_with?(env.vm_image, "/#{env.vm_name}.img")
    assert env.command_timeout_ms == 30_000
  end

  test "accepts explicit overrides without mutating path semantics" do
    env =
      Env.load(%{
        vm_name: "twq-ci",
        vm_image: "/tmp/twq-ci.img",
        vcpus: 8,
        memory: "12G",
        mac_ref_host: "m5-host"
      })

    assert env.vm_name == "twq-ci"
    assert env.vm_image == "/tmp/twq-ci.img"
    assert env.vcpus == "8"
    assert env.memory == "12G"
    assert env.mac_ref_host == "m5-host"
  end

  test "builds script environment variables" do
    env = Env.load(%{vm_name: "twq-dev", vm_image: "/tmp/twq-dev.img"})
    script_env = Env.script_env(env)

    assert script_env["TWQ_VM_NAME"] == "twq-dev"
    assert script_env["TWQ_VM_IMAGE"] == "/tmp/twq-dev.img"
    assert Map.has_key?(script_env, "TWQ_GUEST_ROOT")
  end
end
