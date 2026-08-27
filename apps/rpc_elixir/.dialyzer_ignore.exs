# Everything under test/support is deliberately invalid. The fixtures exist to
# prove the library copes with specs that lie: a handler returning a struct where
# the spec says an atom, a `ts_type/0` returning a non-binary, an output that does
# not match its own @spec. Dialyzer is right about every one of them, which is the
# point, so the whole directory is excluded rather than annotated function by
# function.
[
  ~r{^test/support/},

  # Phoenix is an optional integration, deliberately not a dependency, so
  # `Phoenix.CodeReloader` is genuinely absent from the PLT. The call site guards
  # with `Code.ensure_loaded?/1`, which dialyzer cannot see through.
  {"lib/rpc_elixir/watcher.ex", :unknown_function}
]
