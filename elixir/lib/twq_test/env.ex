defmodule TwqTest.Env do
  @moduledoc """
  Resolves host-side paths and defaults for the test harness.
  """

  @enforce_keys [
    :repo_root,
    :project_root,
    :scripts_dir,
    :artifacts_root,
    :zig_prefix,
    :zig_cache_dir,
    :zig_global_cache_dir,
    :probe_bin,
    :workqueue_probe_bin,
    :swift_async_smoke_bin,
    :swift_taskgroup_probe_bin,
    :swift_dispatch_probe_bin,
    :pthread_include_dir,
    :pthread_manual_so,
    :pthread_stage_dir,
    :swift_distfile,
    :swift_toolchain_root,
    :swift_stage_dir,
    :swift_probe_profile,
    :swift_probe_filter,
    :vm_base_dir,
    :vm_run_dir,
    :vm_name,
    :vm_image,
    :vcpus,
    :memory,
    :serial_log,
    :guest_root,
    :mac_ref_host,
    :command_timeout_ms
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          repo_root: String.t(),
          project_root: String.t(),
          scripts_dir: String.t(),
          artifacts_root: String.t(),
          zig_prefix: String.t(),
          zig_cache_dir: String.t(),
          zig_global_cache_dir: String.t(),
          probe_bin: String.t(),
          workqueue_probe_bin: String.t(),
          swift_async_smoke_bin: String.t(),
          swift_taskgroup_probe_bin: String.t(),
          swift_dispatch_probe_bin: String.t(),
          pthread_include_dir: String.t(),
          pthread_manual_so: String.t(),
          pthread_stage_dir: String.t(),
          swift_distfile: String.t(),
          swift_toolchain_root: String.t(),
          swift_stage_dir: String.t(),
          swift_probe_profile: String.t(),
          swift_probe_filter: String.t(),
          vm_base_dir: String.t(),
          vm_run_dir: String.t(),
          vm_name: String.t(),
          vm_image: String.t(),
          vcpus: String.t(),
          memory: String.t(),
          serial_log: String.t(),
          guest_root: String.t(),
          mac_ref_host: String.t(),
          command_timeout_ms: pos_integer()
        }

  @spec load(map()) :: t()
  def load(overrides \\ %{}) when is_map(overrides) do
    repo_root = repo_root()
    project_root = Path.join(repo_root, "elixir")

    artifacts_root =
      path_value(
        overrides,
        :artifacts_root,
        "TWQ_ARTIFACTS_ROOT",
        Path.expand("../artifacts", repo_root)
      )

    zig_prefix =
      path_value(
        overrides,
        :zig_prefix,
        "TWQ_ZIG_PREFIX",
        Path.join(artifacts_root, "zig/prefix")
      )

    zig_cache_dir =
      path_value(
        overrides,
        :zig_cache_dir,
        "TWQ_ZIG_CACHE_DIR",
        Path.join(artifacts_root, "zig/cache")
      )

    zig_global_cache_dir =
      path_value(
        overrides,
        :zig_global_cache_dir,
        "TWQ_ZIG_GLOBAL_CACHE_DIR",
        Path.join(artifacts_root, "zig/global-cache")
      )

    probe_bin =
      path_value(
        overrides,
        :probe_bin,
        "TWQ_PROBE_BIN",
        Path.join(zig_prefix, "bin/twq-probe-stub")
      )

    workqueue_probe_bin =
      path_value(
        overrides,
        :workqueue_probe_bin,
        "TWQ_WORKQUEUE_PROBE_BIN",
        Path.join(zig_prefix, "bin/twq-workqueue-probe")
      )

    swift_async_smoke_bin =
      path_value(
        overrides,
        :swift_async_smoke_bin,
        "TWQ_SWIFT_ASYNC_SMOKE_BIN",
        Path.join(artifacts_root, "swift/bin/twq-swift-async-smoke")
      )

    swift_taskgroup_probe_bin =
      path_value(
        overrides,
        :swift_taskgroup_probe_bin,
        "TWQ_SWIFT_TASKGROUP_PROBE_BIN",
        Path.join(artifacts_root, "swift/bin/twq-swift-taskgroup-precheck")
      )

    swift_dispatch_probe_bin =
      path_value(
        overrides,
        :swift_dispatch_probe_bin,
        "TWQ_SWIFT_DISPATCH_PROBE_BIN",
        Path.join(artifacts_root, "swift/bin/twq-swift-dispatch-control")
      )

    pthread_include_dir =
      path_value(
        overrides,
        :pthread_include_dir,
        "TWQ_PTHREAD_INCLUDE_DIR",
        "/usr/src/include"
      )

    pthread_manual_so =
      path_value(
        overrides,
        :pthread_manual_so,
        "TWQ_LIBPTHREAD_MANUAL_SO",
        "/tmp/twqlibobj/usr/src/amd64.amd64/lib/libthr/libthr.so.3.full.manual"
      )

    pthread_stage_dir =
      path_value(
        overrides,
        :pthread_stage_dir,
        "TWQ_LIBPTHREAD_STAGE_DIR",
        Path.join(artifacts_root, "libthr-stage")
      )

    swift_distfile =
      path_value(
        overrides,
        :swift_distfile,
        "TWQ_SWIFT_DISTFILE",
        "/Users/me/wip-rnx/freebsd-swift630-artifacts/distfiles/swift-6.3-RELEASE-freebsd15-x86_64-selfhosted.tar.gz"
      )

    swift_toolchain_root =
      path_value(
        overrides,
        :swift_toolchain_root,
        "TWQ_SWIFT_TOOLCHAIN_ROOT",
        "/Users/me/wip-rnx/nx-/swift-source-vx-modified/install/rnx-vx-swift63-selfhost-install5/usr"
      )

    swift_stage_dir =
      path_value(
        overrides,
        :swift_stage_dir,
        "TWQ_SWIFT_STAGE_DIR",
        Path.join(artifacts_root, "swift-stage")
      )

    swift_probe_profile =
      string_value(
        overrides,
        :swift_probe_profile,
        "TWQ_SWIFT_PROBE_PROFILE",
        app_default(:default_swift_probe_profile)
      )

    swift_probe_filter =
      string_value(
        overrides,
        :swift_probe_filter,
        "TWQ_SWIFT_PROBE_FILTER",
        app_default(:default_swift_probe_filter)
      )

    vm_base_dir =
      path_value(overrides, :vm_base_dir, "TWQ_VM_BASE_DIR", Path.expand("../vm/base", repo_root))

    vm_run_dir =
      path_value(overrides, :vm_run_dir, "TWQ_VM_RUN_DIR", Path.expand("../vm/runs", repo_root))

    vm_name = string_value(overrides, :vm_name, "TWQ_VM_NAME", app_default(:default_vm_name))

    vm_image =
      path_value(overrides, :vm_image, "TWQ_VM_IMAGE", Path.join(vm_run_dir, "#{vm_name}.img"))

    vcpus = string_value(overrides, :vcpus, "TWQ_VM_VCPUS", app_default(:default_vcpus))
    memory = string_value(overrides, :memory, "TWQ_VM_MEMORY", app_default(:default_memory))

    serial_log =
      path_value(
        overrides,
        :serial_log,
        "TWQ_SERIAL_LOG",
        Path.join(artifacts_root, "#{vm_name}.serial.log")
      )

    guest_root =
      path_value(
        overrides,
        :guest_root,
        "TWQ_GUEST_ROOT",
        Path.join(vm_run_dir, "#{vm_name}.root")
      )

    mac_ref_host =
      string_value(overrides, :mac_ref_host, "TWQ_MAC_REF_HOST", app_default(:mac_ref_host))

    command_timeout_ms =
      integer_value(
        overrides,
        :command_timeout_ms,
        "TWQ_COMMAND_TIMEOUT_MS",
        app_default(:command_timeout_ms)
      )

    %__MODULE__{
      repo_root: repo_root,
      project_root: project_root,
      scripts_dir: Path.join(repo_root, "scripts/bhyve"),
      artifacts_root: artifacts_root,
      zig_prefix: zig_prefix,
      zig_cache_dir: zig_cache_dir,
      zig_global_cache_dir: zig_global_cache_dir,
      probe_bin: probe_bin,
      workqueue_probe_bin: workqueue_probe_bin,
      swift_async_smoke_bin: swift_async_smoke_bin,
      swift_taskgroup_probe_bin: swift_taskgroup_probe_bin,
      swift_dispatch_probe_bin: swift_dispatch_probe_bin,
      pthread_include_dir: pthread_include_dir,
      pthread_manual_so: pthread_manual_so,
      pthread_stage_dir: pthread_stage_dir,
      swift_distfile: swift_distfile,
      swift_toolchain_root: swift_toolchain_root,
      swift_stage_dir: swift_stage_dir,
      swift_probe_profile: swift_probe_profile,
      swift_probe_filter: swift_probe_filter,
      vm_base_dir: vm_base_dir,
      vm_run_dir: vm_run_dir,
      vm_name: vm_name,
      vm_image: vm_image,
      vcpus: vcpus,
      memory: memory,
      serial_log: serial_log,
      guest_root: guest_root,
      mac_ref_host: mac_ref_host,
      command_timeout_ms: command_timeout_ms
    }
  end

  @spec script_env(t()) :: map()
  def script_env(%__MODULE__{} = env) do
    base = %{
      "TWQ_VM_NAME" => env.vm_name,
      "TWQ_VM_IMAGE" => env.vm_image,
      "TWQ_VM_VCPUS" => env.vcpus,
      "TWQ_VM_MEMORY" => env.memory,
      "TWQ_SERIAL_LOG" => env.serial_log,
      "TWQ_GUEST_ROOT" => env.guest_root,
      "TWQ_ARTIFACTS_ROOT" => env.artifacts_root,
      "TWQ_PROBE_BIN" => env.probe_bin,
      "TWQ_WORKQUEUE_PROBE_BIN" => env.workqueue_probe_bin,
      "TWQ_SWIFT_ASYNC_SMOKE_BIN" => env.swift_async_smoke_bin,
      "TWQ_SWIFT_TASKGROUP_PROBE_BIN" => env.swift_taskgroup_probe_bin,
      "TWQ_SWIFT_DISPATCH_PROBE_BIN" => env.swift_dispatch_probe_bin,
      "TWQ_PTHREAD_INCLUDE_DIR" => env.pthread_include_dir,
      "TWQ_LIBPTHREAD_MANUAL_SO" => env.pthread_manual_so,
      "TWQ_LIBPTHREAD_STAGE_DIR" => env.pthread_stage_dir,
      "TWQ_SWIFT_DISTFILE" => env.swift_distfile,
      "TWQ_SWIFT_TOOLCHAIN_ROOT" => env.swift_toolchain_root,
      "TWQ_SWIFT_STAGE_DIR" => env.swift_stage_dir,
      "TWQ_SWIFT_PROBE_PROFILE" => env.swift_probe_profile,
      "TWQ_SWIFT_PROBE_FILTER" => env.swift_probe_filter
    }

    [
      "TWQ_PREPARE_LIBTHR_STAGE",
      "TWQ_PREPARE_LIBDISPATCH_STAGE",
      "TWQ_PREPARE_SWIFT_STAGE",
      "TWQ_SWIFT_CONCURRENCY_OVERRIDE_SO",
      "TWQ_SWIFT_RUNTIME_TRACE"
    ]
    |> Enum.reduce(base, fn key, acc ->
      case System.get_env(key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end

  defp app_default(key) do
    Application.fetch_env!(:twq_test, key)
  end

  defp string_value(overrides, key, env_var, default) do
    overrides
    |> Map.get(key)
    |> case do
      nil -> System.get_env(env_var, default)
      value -> to_string(value)
    end
  end

  defp integer_value(overrides, key, env_var, default) do
    overrides
    |> Map.get(key)
    |> case do
      nil -> System.get_env(env_var, Integer.to_string(default)) |> String.to_integer()
      value when is_integer(value) -> value
      value -> String.to_integer(to_string(value))
    end
  end

  defp path_value(overrides, key, env_var, default) do
    overrides
    |> Map.get(key)
    |> case do
      nil -> System.get_env(env_var, default)
      value -> Path.expand(to_string(value))
    end
  end
end
