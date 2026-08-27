defmodule RpcElixir.Codegen.Brands do
  @moduledoc false
  # Branded wire types: built-in brands (datetime/date/decimal/...), custom
  # `ts_type/0` brands, their declarations, and collision validation against
  # reserved names, struct interfaces, and procedure interfaces.

  import RpcElixir.Codegen.Shared

  alias RpcElixir.Types.Builtins

  @builtin_brands Map.new(Builtins.all(), fn b ->
                    {b.kind, {b.ts_brand, Builtins.brand_decl(b.ts_brand, b.ts_base)}}
                  end)

  @brand_doc "/** Branded wire value — nominally distinct from its base type; the client does not auto-convert it. */\n"

  @builtin_brand_names @builtin_brands |> Map.values() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

  # TS primitives/lib types and structural names the generated file already declares or imports.
  # A custom ts_type/0 claiming any of these produces an uncompilable .gen.ts.
  @ts_reserved_names MapSet.new(
                       ~w(string number boolean Date null undefined unknown never any object void
                          symbol bigint PaginatedResponse RpcError createClient Client
                          rpcMethod RpcMethod
                          Procedures ProcedureName RpcClient createRpcClient _procedures)
                     )

  def emit_branded_types(procedures) do
    procedures
    |> Enum.flat_map(fn proc -> [proc.input, proc.output, proc.error] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(MapSet.new(), fn ir, acc -> MapSet.union(acc, collect_brands(ir)) end)
    |> Enum.sort()
    |> Enum.map_join("", fn {_ts_name, decl} -> @brand_doc <> decl end)
  end

  def validate_brand_collisions!(procedures, struct_types, name_map) do
    pairs =
      procedures
      |> Enum.flat_map(fn proc -> [proc.input, proc.output, proc.error] end)
      |> Enum.flat_map(&custom_brand_pairs/1)
      |> Enum.uniq()

    struct_names = MapSet.new(struct_types, & &1.__ts_name__)
    proc_names = MapSet.new(Map.values(name_map))

    for {ts_name, mod} <- pairs do
      cond do
        MapSet.member?(@builtin_brand_names, ts_name) ->
          raise brand_collision_error(mod, ts_name, "a reserved built-in brand name")

        MapSet.member?(@ts_reserved_names, ts_name) ->
          raise brand_collision_error(
                  mod,
                  ts_name,
                  "a reserved TypeScript or generated type name"
                )

        MapSet.member?(struct_names, ts_name) ->
          raise brand_collision_error(mod, ts_name, "a generated struct interface name")

        MapSet.member?(proc_names, ts_name) ->
          raise brand_collision_error(mod, ts_name, "a generated procedure interface name")

        true ->
          :ok
      end
    end

    pairs
    |> Enum.group_by(fn {ts_name, _mod} -> ts_name end, fn {_ts_name, mod} -> mod end)
    |> Enum.each(fn {ts_name, mods} ->
      case Enum.uniq(mods) do
        [_single] ->
          :ok

        many ->
          raise "Codegen: TypeScript brand #{inspect(ts_name)} is claimed by multiple custom " <>
                  "types (#{Enum.map_join(many, ", ", &inspect/1)}). Give each a distinct ts_type/0."
      end
    end)
  end

  defp brand_collision_error(mod, ts_name, what) do
    "Codegen: #{inspect(mod)}.ts_type/0 returned #{inspect(ts_name)}, which collides with " <>
      "#{what}. Choose a different name."
  end

  defp custom_brand_pairs(nil), do: []

  defp custom_brand_pairs(%{kind: "custom", module: mod, inner: inner}) do
    case custom_ts_type(mod) do
      nil ->
        custom_brand_pairs(inner)

      ts_name ->
        validate_branded_base!(inner)
        [{ts_name, mod}]
    end
  end

  defp custom_brand_pairs(%{kind: "object", fields: fields}) do
    fields |> Map.values() |> Enum.flat_map(&custom_brand_pairs/1)
  end

  defp custom_brand_pairs(%{kind: _k, inner: inner}), do: custom_brand_pairs(inner)
  defp custom_brand_pairs(_), do: []

  defp validate_branded_base!(inner), do: _ = branded_base_type(inner)

  defp branded_base_type(%{kind: "primitive", type: "string"}), do: "string"

  defp branded_base_type(%{kind: "primitive", type: t}) when t in ["integer", "float"],
    do: "number"

  defp branded_base_type(inner) do
    raise "Codegen: ts_type/0 emits a branded type, but its wire_spec/0 " <>
            "resolves to #{inspect(inner)}. Branded types require a string or number wire " <>
            ~s(%{kind: "primitive", type: "string" | "integer" | "float"}.)
  end

  defp collect_brands(nil), do: MapSet.new()

  defp collect_brands(%{kind: k}) when is_map_key(@builtin_brands, k),
    do: MapSet.new([Map.fetch!(@builtin_brands, k)])

  defp collect_brands(%{kind: "custom", module: mod, inner: inner}) do
    case custom_ts_type(mod) do
      nil ->
        collect_brands(inner)

      ts_name ->
        base = branded_base_type(inner)
        MapSet.new([{ts_name, Builtins.brand_decl(ts_name, base)}])
    end
  end

  defp collect_brands(%{kind: "object", fields: fields}) do
    fields
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn ir, acc -> MapSet.union(acc, collect_brands(ir)) end)
  end

  defp collect_brands(%{kind: _k, inner: inner}), do: collect_brands(inner)

  defp collect_brands(_), do: MapSet.new()
end
