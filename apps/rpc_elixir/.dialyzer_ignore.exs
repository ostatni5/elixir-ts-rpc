# Dialyzer warnings we deliberately accept. Each entry is {file, warning_type}
# so a *different* (genuinely new) warning in the same file still surfaces.
[
  # Optional Phoenix integration: `trigger/1` calls Phoenix.CodeReloader only
  # behind `Code.ensure_loaded?/1`. Phoenix is not a dependency, so dialyzer
  # can't resolve the call.
  {"lib/rpc_elixir/watcher.ex", :unknown_function},

  # Test fixtures intentionally carry mismatched @specs to exercise the
  # codegen and runtime error-handling paths.
  {"test/support/router_fixtures.ex", :invalid_contract},
  {"test/support/codegen_fixtures.ex", :invalid_contract},

  # Ecto schemas don't define a `t/0` type; the codegen reads the struct, not
  # the type. The EctoTimestamp fixture references TimestampedSchema.t/0 on
  # purpose to cover that case.
  {"test/support/codegen_fixtures.ex", :unknown_type},

  # NonStringBrand.ts_type/0 returns a non-binary on purpose, to test that the
  # codegen rejects invalid custom-type metadata.
  {"test/support/typespec_fixtures.ex", :callback_type_mismatch}
]
