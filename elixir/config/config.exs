import Config

config :twq_test,
  default_vm_name: "twq-dev",
  default_vcpus: "4",
  default_memory: "8G",
  command_timeout_ms: 30_000,
  default_swift_probe_profile: "validation",
  default_swift_probe_filter: "",
  mac_ref_host: "macos-ref.local"
