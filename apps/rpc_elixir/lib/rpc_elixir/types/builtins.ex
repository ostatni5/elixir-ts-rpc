defmodule RpcElixir.Types.Builtins do
  @moduledoc false
  # Single source of truth for the built-in branded scalar types: the Elixir
  # module whose `.t()` maps to them, the IR `kind` string they resolve to, and
  # the TypeScript brand name plus base type the codegen emits. Every consumer
  # (the walker, the IR→TS renderer, the brand-declaration emitter, and the
  # validator/serializer in RpcElixir.Types) derives from this table so the
  # mapping is stated exactly once.

  @type t :: %{kind: String.t(), module: module(), ts_brand: String.t(), ts_base: String.t()}

  @rows [
    %{kind: "date", module: Date, ts_brand: "DateString", ts_base: "string"},
    %{kind: "datetime", module: DateTime, ts_brand: "DateTimeString", ts_base: "string"},
    %{
      kind: "naive_datetime",
      module: NaiveDateTime,
      ts_brand: "NaiveDateTimeString",
      ts_base: "string"
    },
    %{kind: "time", module: Time, ts_brand: "ISOTime", ts_base: "string"},
    %{kind: "decimal", module: Decimal, ts_brand: "DecimalString", ts_base: "string"}
  ]

  @spec all() :: [t()]
  def all, do: @rows

  @spec kinds() :: [String.t()]
  def kinds, do: Enum.map(@rows, & &1.kind)

  @spec by_kind(String.t()) :: t() | nil
  def by_kind(kind), do: Enum.find(@rows, &(&1.kind == kind))

  @spec by_module(module()) :: t() | nil
  def by_module(module), do: Enum.find(@rows, &(&1.module == module))

  @doc "Renders the TypeScript branded-type alias declaration for `ts_name`/`base`."
  @spec brand_decl(String.t(), String.t()) :: String.t()
  def brand_decl(ts_name, base) do
    ~s(export type #{ts_name} = #{base} & { readonly __brand: "#{ts_name}" };\n)
  end
end
