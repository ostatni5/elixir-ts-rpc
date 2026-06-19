defmodule RpcElixir.Types do
  @moduledoc """
  Type system for RPC procedure input/output specs.

  Three entry points: `resolve/1` normalizes a shorthand spec into the internal
  IR map, `validate/2` checks untrusted input against a spec, and `serialize/2`
  prepares handler output for JSON encoding.

  ## Atom keys in validated input

  After a successful `validate/2` call, object values are returned with
  **atom keys** (e.g. `%{id: "abc"}`), not string keys. Handler functions
  therefore receive atom-keyed maps and should pattern-match accordingly:

      def get(%{id: id}, _ctx), do: ...   # correct
      def get(%{"id" => id}, _ctx), do: ... # wrong, key will be missing
  """

  @typedoc "Internal IR map used throughout the type system. Always has a `kind` string key."
  @type internal_spec :: %{optional(atom()) => term(), kind: String.t()}

  @temporal_kinds RpcElixir.Types.Builtins.kinds() -- ["decimal"]

  @doc "Converts a shorthand spec term (atom, tagged tuple, or map) to an `internal_spec` IR map."
  @spec resolve(
          :string
          | :integer
          | :float
          | :boolean
          | {:optional, term()}
          | {:nullable, term()}
          | {:list, term()}
          | {:stream, term()}
          | internal_spec()
          | map()
        ) :: internal_spec()
  def resolve(:string), do: %{kind: "primitive", type: "string"}
  def resolve(:integer), do: %{kind: "primitive", type: "integer"}
  def resolve(:float), do: %{kind: "primitive", type: "float"}
  def resolve(:boolean), do: %{kind: "primitive", type: "boolean"}

  def resolve({:optional, t}), do: %{kind: "optional", inner: resolve(t)}
  def resolve({:nullable, t}), do: %{kind: "nullable", inner: resolve(t)}
  def resolve({:list, t}), do: %{kind: "list", inner: resolve(t)}
  def resolve({:stream, t}), do: %{kind: "list", inner: resolve(t)}
  def resolve(%{kind: k} = already_resolved) when is_binary(k), do: already_resolved

  def resolve(map) when is_map(map) and not is_struct(map) do
    %{kind: "object", fields: Map.new(map, fn {k, v} -> {k, resolve(v)} end)}
  end

  def resolve(other) do
    raise ArgumentError,
          "unsupported inline spec: #{inspect(other)}, " <>
            "use :string, :integer, :float, :boolean, {:optional, t}, {:nullable, t}, " <>
            "{:list, t}, or a plain map for object shapes"
  end

  @doc """
  Validates user-supplied `value` against `spec`, returning `{:ok, coerced}` or `{:error, tree}`.

  `spec` may be a shorthand spec term (atom, tagged tuple, or map, see `resolve/1`)
  or an already-resolved IR map. Intended for untrusted input (decoded JSON), so
  contract violations come back as error trees rather than raises.

  Object values in the returned `{:ok, coerced}` tuple always have **atom keys**. See the
  module doc for details.
  """
  @spec validate(term(), term()) :: {:ok, term()} | {:error, map()}
  def validate(spec, value), do: do_validate(resolve(spec), value)

  @doc """
  Serializes a server-produced `value` against `spec` into a JSON-encodable shape.

  `spec` may be a shorthand spec term (atom, tagged tuple, or map, see `resolve/1`)
  or an already-resolved IR map. Assumes `value` already conforms to `spec` (e.g. fresh
  from a handler) and **raises** on contract violations such as missing required fields.
  These indicate programmer error, not bad input.
  """
  @spec serialize(term(), term()) :: term()
  def serialize(spec, value), do: do_serialize(resolve(spec), value)

  defp do_validate(%{kind: "primitive", type: "string"}, v) when is_binary(v), do: {:ok, v}
  defp do_validate(%{kind: "primitive", type: "integer"}, v) when is_integer(v), do: {:ok, v}
  defp do_validate(%{kind: "primitive", type: "float"}, v) when is_float(v), do: {:ok, v}
  defp do_validate(%{kind: "primitive", type: "float"}, v) when is_integer(v), do: {:ok, v * 1.0}
  defp do_validate(%{kind: "primitive", type: "boolean"}, v) when is_boolean(v), do: {:ok, v}

  defp do_validate(%{kind: "nullable"}, nil), do: {:ok, nil}
  defp do_validate(%{kind: "nullable", inner: inner}, v), do: do_validate(inner, v)

  defp do_validate(%{kind: "optional", inner: inner}, v), do: do_validate(inner, v)

  defp do_validate(%{kind: "enum", values: values}, v) when is_binary(v) do
    if v in values do
      to_existing_atom_or_error(v, values)
    else
      leaf_error("expected one of #{inspect(values)}, got #{inspect(v)}")
    end
  end

  defp do_validate(%{kind: "list", inner: inner}, v) when is_list(v) do
    {values, errors} =
      v
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {item, idx}, {vals, errs} ->
        case do_validate(inner, item) do
          {:ok, val} -> {[val | vals], errs}
          {:error, tree} -> {vals, Map.put(errs, Integer.to_string(idx), tree)}
        end
      end)

    if map_size(errors) == 0 do
      {:ok, Enum.reverse(values)}
    else
      {:error, errors}
    end
  end

  defp do_validate(%{kind: "object", fields: fields}, v) when is_map(v) do
    atom_map = atomize_keys(v)
    declared = MapSet.new(Map.keys(fields))

    unknown_errors =
      atom_map
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(declared, &1))
      |> Map.new(fn key -> {to_string(key), ["unexpected field"]} end)

    {values, errors} =
      Enum.reduce(fields, {%{}, unknown_errors}, fn {field, field_spec}, {vals, errs} ->
        case validate_field(field, field_spec, atom_map) do
          {:ok, :absent} -> {vals, errs}
          {:ok, val} -> {Map.put(vals, field, val), errs}
          {:error, tree} -> {vals, Map.put(errs, Atom.to_string(field), tree)}
        end
      end)

    if map_size(errors) == 0, do: {:ok, values}, else: {:error, errors}
  end

  defp do_validate(%{kind: "custom", module: mod, inner: inner}, v) do
    case do_validate(inner, v) do
      {:ok, wire} ->
        deserialize_custom(mod, wire)

      {:error, _} ->
        accept_domain_value(mod, v)
    end
  end

  defp do_validate(%{kind: "custom", inner: inner}, v) do
    case do_validate(inner, v) do
      {:ok, _} = ok -> ok
      {:error, _} -> {:ok, v}
    end
  end

  defp do_validate(%{kind: "date"}, %Date{} = v), do: {:ok, v}
  defp do_validate(%{kind: "datetime"}, %DateTime{} = v), do: {:ok, v}
  defp do_validate(%{kind: "naive_datetime"}, %NaiveDateTime{} = v), do: {:ok, v}
  defp do_validate(%{kind: "time"}, %Time{} = v), do: {:ok, v}

  defp do_validate(%{kind: "date"}, v) when is_binary(v) do
    case Date.from_iso8601(v) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> leaf_error("expected ISO 8601 date, got #{inspect(v)}")
    end
  end

  defp do_validate(%{kind: "naive_datetime"}, v) when is_binary(v) do
    case NaiveDateTime.from_iso8601(v) do
      {:ok, naive} -> {:ok, naive}
      {:error, _} -> leaf_error("expected ISO 8601 naive datetime, got #{inspect(v)}")
    end
  end

  defp do_validate(%{kind: "time"}, v) when is_binary(v) do
    case Time.from_iso8601(v) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> leaf_error("expected ISO 8601 time, got #{inspect(v)}")
    end
  end

  defp do_validate(%{kind: "datetime"}, v) when is_binary(v) do
    case DateTime.from_iso8601(v) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> leaf_error("expected ISO 8601 datetime, got #{inspect(v)}")
    end
  end

  # Broad is_struct guard accepts an already-materialized %Decimal{} (or similar) without invoking the library.
  defp do_validate(%{kind: "decimal"}, v) when is_struct(v), do: {:ok, v}
  defp do_validate(%{kind: "decimal"}, v) when is_binary(v), do: parse_decimal(v)

  defp do_validate(expected_spec, value) do
    leaf_error("expected #{inspect(expected_spec)}, got #{inspect(value)}")
  end

  # A spec value present in `values` is normally a known atom, but untrusted input
  # could reach an enum whose atom was never materialized. Rescue keeps validate/2
  # total (returns an error tree) instead of raising on the caller.
  defp to_existing_atom_or_error(v, values) do
    {:ok, String.to_existing_atom(v)}
  rescue
    ArgumentError -> leaf_error("expected one of #{inspect(values)}, got #{inspect(v)}")
  end

  defp leaf_error(msg), do: {:error, %{"_" => [msg]}}

  # Reached only after `v` failed wire validation. Accepting it must not become an
  # input-validation bypass. JSON never decodes to a struct, so a struct can only be
  # an in-process domain value and is safe. Plain maps/lists are the JSON-shaped
  # bypass vectors and are rejected. Scalars are deferred to the module's `serialize/1`.
  defp accept_domain_value(_mod, v) when is_struct(v), do: {:ok, v}

  defp accept_domain_value(mod, v) when is_map(v) or is_list(v) do
    leaf_error(domain_value_mismatch(mod))
  end

  defp accept_domain_value(mod, v) do
    mod.serialize(v)
    {:ok, v}
  rescue
    e -> leaf_error(domain_value_mismatch(mod) <> ": " <> Exception.message(e))
  catch
    kind, reason -> leaf_error(domain_value_mismatch(mod) <> ": #{kind} #{inspect(reason)}")
  end

  defp domain_value_mismatch(mod),
    do: "value matches neither wire spec nor source type for #{inspect(mod)}"

  defp deserialize_custom(mod, wire) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :deserialize, 1) do
      case mod.deserialize(wire) do
        {:ok, domain} -> {:ok, domain}
        {:error, reason} -> leaf_error("custom type rejected value: #{inspect(reason)}")
      end
    else
      {:ok, wire}
    end
  end

  defp parse_decimal(v) do
    # apply/3 defeats compile-time resolution, avoiding a warning for the optional Decimal dep.
    if Code.ensure_loaded?(Decimal) and function_exported?(Decimal, :parse, 1) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      case apply(Decimal, :parse, [v]) do
        {decimal, ""} -> {:ok, decimal}
        _ -> leaf_error("expected decimal string, got #{inspect(v)}")
      end
    else
      {:ok, v}
    end
  end

  defp validate_field(field, %{kind: "optional", inner: inner}, map) do
    case Map.fetch(map, field) do
      {:ok, val} -> do_validate(inner, val)
      :error -> {:ok, :absent}
    end
  end

  defp validate_field(field, field_spec, map) do
    case Map.fetch(map, field) do
      {:ok, val} -> do_validate(field_spec, val)
      :error -> {:error, ["missing required field"]}
    end
  end

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        try do
          {String.to_existing_atom(k), v}
        rescue
          ArgumentError -> {k, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  defp do_serialize(%{kind: "nullable"}, nil), do: nil
  defp do_serialize(%{kind: "nullable", inner: inner}, v), do: do_serialize(inner, v)
  defp do_serialize(%{kind: "optional", inner: inner}, v), do: do_serialize(inner, v)
  defp do_serialize(%{kind: "primitive"}, v), do: v
  defp do_serialize(%{kind: "enum"}, v) when is_atom(v), do: Atom.to_string(v)
  defp do_serialize(%{kind: "enum"}, v) when is_binary(v), do: v

  defp do_serialize(%{kind: "list", inner: inner}, v) when is_list(v),
    do: Enum.map(v, &do_serialize(inner, &1))

  defp do_serialize(%{kind: "object", fields: fields}, v) when is_map(v) do
    Enum.reduce(fields, %{}, fn {field, field_spec}, acc ->
      case fetch_field(v, field) do
        {:ok, val} -> Map.put(acc, field, do_serialize(field_spec, val))
        :error -> serialize_missing_field(field, field_spec, acc)
      end
    end)
  end

  defp do_serialize(%{kind: "custom", module: mod, inner: inner}, v),
    do: do_serialize(inner, mod.serialize(v))

  defp do_serialize(%{kind: "date"}, %Date{} = v), do: Date.to_iso8601(v)

  defp do_serialize(%{kind: "datetime"}, %DateTime{} = v), do: DateTime.to_iso8601(v)

  defp do_serialize(%{kind: "naive_datetime"}, %NaiveDateTime{} = v),
    do: NaiveDateTime.to_iso8601(v)

  defp do_serialize(%{kind: "time"}, %Time{} = v), do: Time.to_iso8601(v)

  defp do_serialize(%{kind: k}, v)
       when k in @temporal_kinds and is_binary(v),
       do: v

  defp do_serialize(%{kind: "decimal"}, v) when is_binary(v), do: v
  defp do_serialize(%{kind: "decimal"}, v), do: to_string(v)

  defp do_serialize(spec, value) do
    raise ArgumentError,
          "cannot serialize value #{inspect(value)} against spec #{inspect(spec)}"
  end

  defp serialize_missing_field(_field, %{kind: "optional"}, acc), do: acc

  defp serialize_missing_field(field, _field_spec, _acc) do
    raise ArgumentError, "missing required field #{inspect(field)} during serialization"
  end

  defp fetch_field(map, field) do
    case Map.fetch(map, field) do
      :error -> Map.fetch(map, Atom.to_string(field))
      found -> found
    end
  end
end
