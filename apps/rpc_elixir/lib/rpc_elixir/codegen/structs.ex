defmodule RpcElixir.Codegen.Structs do
  @moduledoc false
  # Struct-keyed shared types (Feature 4): collect every struct reachable from
  # the procedure IR, disambiguate their TypeScript names, and emit one
  # `export interface` per struct with cross-references resolved by name.

  import RpcElixir.Codegen.Shared

  alias RpcElixir.Codegen.Render

  def collect_struct_types(procedures, name_map) do
    structs =
      procedures
      |> Enum.flat_map(fn proc -> [proc.input, proc.output, proc.error] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(&walk_for_structs/1)
      |> dedup_keeping_fullest()

    ts_names = disambiguate_struct_names(Enum.map(structs, & &1.struct))

    structs
    |> Enum.map(fn obj -> Map.put(obj, :__ts_name__, Map.fetch!(ts_names, obj.struct)) end)
    |> Enum.sort_by(& &1.__ts_name__)
    |> Enum.map(fn obj ->
      Map.put(obj, :__ts_name__, unique_struct_name(obj.__ts_name__, name_map))
    end)
  end

  # Recursive structs produce both a full occurrence and truncated (empty-fields)
  # back-references. Keep the occurrence with the most fields per module so an empty
  # ref can never win the dedup and become the emitted interface.
  defp dedup_keeping_fullest(structs) do
    structs
    |> Enum.group_by(& &1.struct)
    |> Enum.map(fn {_mod, occurrences} -> Enum.max_by(occurrences, &map_size(&1.fields)) end)
  end

  defp unique_struct_name(candidate, name_map) do
    existing = MapSet.new(Map.values(name_map))
    if MapSet.member?(existing, candidate), do: candidate <> "Struct", else: candidate
  end

  defp walk_for_structs(%{kind: "object", struct: _mod, fields: fields} = node) do
    case paginated_item_type(fields) do
      {:ok, inner} ->
        walk_for_structs(inner)

      :not_paginated ->
        nested = fields |> Map.values() |> Enum.flat_map(&walk_for_structs/1)
        [node | nested]
    end
  end

  defp walk_for_structs(%{kind: "object", fields: fields}) do
    case paginated_item_type(fields) do
      {:ok, inner} -> walk_for_structs(inner)
      :not_paginated -> fields |> Map.values() |> Enum.flat_map(&walk_for_structs/1)
    end
  end

  defp walk_for_structs(%{kind: k, inner: inner})
       when k in ["nullable", "optional", "list", "custom"],
       do: walk_for_structs(inner)

  defp walk_for_structs(_), do: []

  defp disambiguate_struct_names([]), do: %{}

  defp disambiguate_struct_names(modules) do
    initial = Map.new(modules, fn m -> {m, [last_segment(m)]} end)
    resolve_collisions(modules, initial)
  end

  defp resolve_collisions(modules, names) do
    by_name = Enum.group_by(modules, fn m -> Enum.join(names[m], "_") end)
    collisions = Enum.filter(by_name, fn {_name, mods} -> length(mods) > 1 end)

    if collisions == [] do
      Map.new(names, fn {m, segs} -> {m, Enum.join(segs, "_")} end)
    else
      names =
        Enum.reduce(collisions, names, fn {_name, mods}, acc ->
          Enum.reduce(mods, acc, fn m, inner_acc ->
            Map.update!(inner_acc, m, &prepend_parent(m, &1))
          end)
        end)

      resolve_collisions(modules, names)
    end
  end

  defp prepend_parent(module, current_segs) do
    parts = Module.split(module)
    taken = length(current_segs)

    if taken >= length(parts),
      do: current_segs,
      else: [Enum.at(parts, length(parts) - taken - 1) | current_segs]
  end

  def emit_struct_type_defs([]), do: ""

  def emit_struct_type_defs(structs) do
    by_struct = Map.new(structs, fn s -> {s.struct, s.__ts_name__} end)
    resolve = by_struct_resolver(by_struct)

    Enum.map_join(structs, "\n", fn obj ->
      props = Render.render_fields(obj.fields, resolve)
      "export interface #{obj.__ts_name__} {\n#{props}}\n"
    end)
  end

  # Nested struct references inside a struct interface body resolve to their
  # disambiguated names via `by_struct` (built from the collected structs) rather than the
  # global struct_types list. Everything else routes through the shared renderer.
  defp by_struct_resolver(by_struct) do
    fn mod, _fields -> Map.get(by_struct, mod, last_segment(mod)) end
  end
end
