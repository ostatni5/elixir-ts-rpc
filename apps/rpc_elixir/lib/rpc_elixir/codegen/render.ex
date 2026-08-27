defmodule RpcElixir.Codegen.Render do
  @moduledoc false
  # IR → TypeScript type rendering: the recursive `ir_to_ts_type/3`, inline
  # object types, top-level `$defs` emission (interfaces / type aliases /
  # RpcError shapes), and the handler name-map that mirrors naming.ts.

  import RpcElixir.Codegen.Shared

  alias RpcElixir.JSON
  alias RpcElixir.Types.Builtins

  @builtin_brand_by_kind Map.new(Builtins.all(), fn b -> {b.kind, b.ts_brand} end)

  # ---------------------------------------------------------------------------
  # Name map — mirrors naming.ts logic
  # ---------------------------------------------------------------------------

  def build_def_keys(procedures) do
    Enum.flat_map(procedures, fn proc ->
      base = proc_base_key(proc)
      ["#{base}.Input", "#{base}.Output", "#{base}.Error"]
    end)
    |> Enum.uniq()
  end

  def build_name_map(def_keys) do
    short_groups = Enum.group_by(def_keys, &short_name/1)

    name_map =
      Enum.reduce(short_groups, %{}, fn {short, keys}, acc ->
        if length(keys) == 1 do
          Map.put(acc, hd(keys), short)
        else
          Enum.reduce(keys, acc, fn key, inner_acc ->
            Map.put(inner_acc, key, full_name(key))
          end)
        end
      end)

    validate_no_collisions!(name_map)
    name_map
  end

  defp validate_no_collisions!(name_map) do
    {_, collisions} =
      Enum.reduce(name_map, {MapSet.new(), []}, fn {key, name}, {seen, colls} ->
        if MapSet.member?(seen, name) do
          {seen, ["#{key} → #{name}" | colls]}
        else
          {MapSet.put(seen, name), colls}
        end
      end)

    if collisions != [] do
      raise "Codegen: cannot resolve unique TypeScript names for these handlers — rename one of the modules to disambiguate:\n  #{Enum.join(collisions, "\n  ")}"
    end
  end

  defp short_name(key) do
    parts = String.split(key, ".")
    rest_parts = Enum.drop(parts, 1)
    rest_parts = Enum.reject(rest_parts, &(&1 == "Handlers"))
    segments_to_pascal(rest_parts)
  end

  defp full_name(key) do
    parts = String.split(key, ".")
    segments_to_pascal(parts)
  end

  defp segments_to_pascal(segments) do
    Enum.map_join(segments, "", &to_pascal_case/1)
  end

  defp to_pascal_case(segment) do
    segment
    |> String.split("_")
    |> Enum.map_join("", fn part ->
      case String.split_at(part, 1) do
        {"", _} -> ""
        {first, rest} -> String.upcase(first) <> rest
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # IR → TypeScript type string
  # ---------------------------------------------------------------------------

  @doc """
  Renders IR to a TypeScript type string, resolving named-struct references via the
  global `struct_types` list. Equivalent to `render_type/2` with the global resolver.
  """
  def ir_to_ts_type(ir, name_map, struct_types) do
    render_type(ir, global_struct_resolver(name_map, struct_types))
  end

  @doc """
  Single recursive IR→TS renderer. `resolve_struct` maps a named struct (module + fields)
  to its TS name or falls back to an inline object. Call sites differ only in which
  closure they pass: `global_struct_resolver/2` for top-level rendering, or a recursive
  closure when descending into struct bodies.
  """
  def render_type(nil, _resolve), do: "null"
  def render_type(%{kind: "primitive", type: "string"}, _resolve), do: "string"
  def render_type(%{kind: "primitive", type: "integer"}, _resolve), do: "number"
  def render_type(%{kind: "primitive", type: "float"}, _resolve), do: "number"
  def render_type(%{kind: "primitive", type: "boolean"}, _resolve), do: "boolean"

  def render_type(%{kind: kind}, _resolve) when is_map_key(@builtin_brand_by_kind, kind) do
    Map.fetch!(@builtin_brand_by_kind, kind)
  end

  def render_type(%{kind: "enum", values: values}, _resolve) do
    Enum.map_join(values, " | ", &JSON.encode!/1)
  end

  def render_type(%{kind: "list", inner: inner}, resolve) do
    ts = render_type(inner, resolve)
    if String.contains?(ts, " | "), do: "(#{ts})[]", else: "#{ts}[]"
  end

  def render_type(%{kind: "nullable", inner: %{kind: "nullable"} = inner}, resolve) do
    render_type(inner, resolve)
  end

  def render_type(%{kind: "nullable", inner: inner}, resolve) do
    "#{render_type(inner, resolve)} | null"
  end

  def render_type(%{kind: "optional", inner: inner}, resolve) do
    render_type(inner, resolve)
  end

  def render_type(%{kind: "custom", module: mod, inner: inner}, resolve) do
    case custom_ts_type(mod) do
      nil -> render_type(inner, resolve)
      brand -> brand
    end
  end

  def render_type(%{kind: "object", fields: fields} = obj, resolve) do
    case paginated_item_type(fields) do
      {:ok, inner} -> "PaginatedResponse<#{render_type(inner, resolve)}>"
      :not_paginated -> render_object(obj, resolve)
    end
  end

  # Fail loudly: a new/misspelled IR kind reaching here would otherwise emit the
  # valid-but-meaningless TS `unknown`, which compiles and slips past the tsc
  # round-trip — shipping broken types silently.
  def render_type(other, _resolve) do
    raise ArgumentError,
          "rpc_elixir codegen: unhandled IR kind #{inspect(kind_of(other))} in ir_to_ts_type/3 — this is a bug in the type pipeline"
  end

  defp render_object(%{kind: "object", struct: mod, fields: fields}, resolve) when is_atom(mod) do
    resolve.(mod, fields)
  end

  defp render_object(%{kind: "object", fields: fields}, resolve) do
    inline_object(fields, resolve)
  end

  defp global_struct_resolver(name_map, struct_types) do
    fn mod, fields ->
      case Enum.find(struct_types, fn s -> s.struct == mod end) do
        nil -> inline_object(fields, global_struct_resolver(name_map, struct_types))
        struct_entry -> struct_entry.__ts_name__
      end
    end
  end

  defp inline_object(fields, resolve) do
    if map_size(fields) == 0 do
      "Record<string, never>"
    else
      props =
        Enum.map_join(fields, "; ", fn {field_name, field_ir} ->
          {inner_ir, optional?} = unwrap_optional(field_ir)
          opt = if optional?, do: "?", else: ""
          "#{emit_prop_key(Atom.to_string(field_name))}#{opt}: #{render_type(inner_ir, resolve)}"
        end)

      "{ #{props} }"
    end
  end

  defp kind_of(%{kind: kind}), do: kind
  defp kind_of(other), do: other

  def inline_object_type(%{kind: "object", fields: fields}, name_map, struct_types) do
    inline_object(fields, global_struct_resolver(name_map, struct_types))
  end

  @doc """
  Renders an object's fields as the body of an `export interface`: one
  `  key?: Type;\\n` line per field. `resolve` is the struct-name resolver threaded
  into `render_type/2`. With `docs: true`, a per-field JSDoc line is prefixed when the
  field IR carries a description.
  """
  def render_fields(fields, resolve, opts \\ []) do
    docs? = Keyword.get(opts, :docs, false)

    Enum.map_join(fields, "", fn {field_name, field_ir} ->
      {inner_ir, optional?} = unwrap_optional(field_ir)
      prop_doc = if docs?, do: maybe_prop_jsdoc(inner_ir), else: ""
      opt = if optional?, do: "?", else: ""
      key = emit_prop_key(Atom.to_string(field_name))
      "#{prop_doc}  #{key}#{opt}: #{render_type(inner_ir, resolve)};\n"
    end)
  end

  # ---------------------------------------------------------------------------
  # Top-level def emission
  # ---------------------------------------------------------------------------

  def emit_all_defs(procedures, name_map, struct_types) do
    procedures
    |> Enum.flat_map(fn proc ->
      base = proc_base_key(proc)

      [
        {proc.input, "#{base}.Input", :input},
        {proc.output, "#{base}.Output", :output},
        {proc.error, "#{base}.Error", :error}
      ]
    end)
    |> Enum.uniq_by(fn {_ir, key, _role} -> key end)
    |> Enum.map_join("\n", fn {ir, key, role} ->
      ts_name = Map.fetch!(name_map, key)
      emit_top_level_def(ir, ts_name, name_map, struct_types, role)
    end)
  end

  defp emit_type_alias(ts_name, ts_type, doc_line \\ "") do
    "#{doc_line}export type #{ts_name} = #{ts_type};\n"
  end

  defp emit_top_level_def(nil, ts_name, _name_map, _struct_types, :error) do
    emit_type_alias(ts_name, "never")
  end

  defp emit_top_level_def(nil, ts_name, _name_map, _struct_types, _role) do
    emit_type_alias(ts_name, "null")
  end

  defp emit_top_level_def(ir, ts_name, name_map, struct_types, :error) do
    case unwrap_nullable_optional(ir) do
      {%{kind: "enum", values: values}, wrappers} ->
        codes = enum_values_to_codes(values)
        emit_type_alias(ts_name, apply_wrappers("DomainError<#{codes}>", wrappers))

      {%{kind: "object", fields: fields}, wrappers} ->
        case object_error_codes(fields) do
          {:ok, codes, detail_fields} ->
            details_ts = details_ts_type(detail_fields, name_map, struct_types)
            inner = "DomainError<#{codes}, #{details_ts}>"
            emit_type_alias(ts_name, apply_wrappers(inner, wrappers))

          :no_code ->
            emit_plain_def(ir, ts_name, name_map, struct_types)
        end

      _ ->
        emit_plain_def(ir, ts_name, name_map, struct_types)
    end
  end

  defp emit_top_level_def(
         %{kind: "object", struct: mod, fields: fields} = ir,
         ts_name,
         name_map,
         struct_types,
         _role
       )
       when is_atom(mod) do
    case paginated_item_type(fields) do
      {:ok, _inner} ->
        emit_plain_def(ir, ts_name, name_map, struct_types)

      :not_paginated ->
        case Enum.find(struct_types, fn s -> s.struct == mod end) do
          nil -> emit_top_level_def(%{ir | struct: nil}, ts_name, name_map, struct_types, :output)
          struct_entry -> emit_type_alias(ts_name, struct_entry.__ts_name__)
        end
    end
  end

  defp emit_top_level_def(
         %{kind: "object", fields: fields} = ir,
         ts_name,
         name_map,
         struct_types,
         _role
       ) do
    case paginated_item_type(fields) do
      {:ok, _inner} ->
        emit_plain_def(ir, ts_name, name_map, struct_types)

      :not_paginated ->
        doc_line = maybe_jsdoc(ir, "")
        props = render_fields(fields, global_struct_resolver(name_map, struct_types), docs: true)
        "#{doc_line}export interface #{ts_name} {\n#{props}}\n"
    end
  end

  defp emit_top_level_def(ir, ts_name, name_map, struct_types, _role) do
    emit_plain_def(ir, ts_name, name_map, struct_types)
  end

  defp emit_plain_def(ir, ts_name, name_map, struct_types) do
    emit_type_alias(ts_name, ir_to_ts_type(ir, name_map, struct_types), maybe_jsdoc(ir, ""))
  end

  defp enum_values_to_codes(values) do
    Enum.map_join(values, " | ", &JSON.encode!/1)
  end

  defp object_error_codes(fields) do
    case Map.get(fields, :code) do
      %{kind: "enum", values: values} ->
        rest = Map.drop(fields, [:code, :message])
        {:ok, enum_values_to_codes(values), rest}

      _ ->
        :no_code
    end
  end

  @doc """
  Returns the raw code values for a procedure's error IR — an enum error's values,
  or an object error's `:code` enum values — or `[]` when the error has no
  discriminable code set. The generated client passes these to `rpcMethod` so
  `.isError` can soundly narrow to the procedure's error type at runtime.
  """
  def error_code_values(nil), do: []

  def error_code_values(ir) do
    case unwrap_nullable_optional(ir) do
      {%{kind: "enum", values: values}, _wrappers} -> values
      {%{kind: "object", fields: %{code: %{kind: "enum", values: values}}}, _wrappers} -> values
      _ -> []
    end
  end

  # The runtime `isError` guard only checks `code`; it never validates `details`
  # (it's `payload.details as Details`). So the generated type must not promise the
  # detail object is always present — it widens to `| undefined`.
  defp details_ts_type(fields, _name_map, _struct_types) when fields == %{}, do: "undefined"

  defp details_ts_type(fields, name_map, struct_types) do
    "#{inline_object_type(%{kind: "object", fields: fields}, name_map, struct_types)} | undefined"
  end

  defp unwrap_nullable_optional(%{kind: "optional", inner: inner}) do
    {core, wrappers} = unwrap_nullable_optional(inner)
    {core, [:optional | wrappers]}
  end

  defp unwrap_nullable_optional(%{kind: "nullable", inner: inner}) do
    {core, wrappers} = unwrap_nullable_optional(inner)
    {core, [:nullable | wrappers]}
  end

  defp unwrap_nullable_optional(ir), do: {ir, []}

  defp apply_wrappers(inner, []), do: inner
  defp apply_wrappers(inner, [:nullable | rest]), do: "#{apply_wrappers(inner, rest)} | null"
  defp apply_wrappers(inner, [:optional | rest]), do: apply_wrappers(inner, rest)

  defp maybe_jsdoc(%{description: desc}, indent) when is_binary(desc) and desc != "" do
    "#{indent}/** #{sanitize_doc(String.trim(desc))} */\n"
  end

  defp maybe_jsdoc(_ir, _indent), do: ""

  defp maybe_prop_jsdoc(%{description: desc}) when is_binary(desc) and desc != "" do
    "  /** #{sanitize_doc(String.trim(desc))} */\n"
  end

  defp maybe_prop_jsdoc(_), do: ""
end
