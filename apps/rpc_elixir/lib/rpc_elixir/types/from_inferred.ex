defmodule RpcElixir.Types.FromInferred do
  @moduledoc """
  EXPERIMENTAL backend that reads signatures inferred by Elixir's set-theoretic
  type system from the `ExCk` BEAM chunk, instead of user-written `@spec`.

  Not the recommended path. Use `RpcElixir.Types.FromSpec` for any real
  workload. This module exists so we can track the new type system as it
  evolves toward a public introspection API.

  Hard caveats:

  * **Private API.** `ExCk` chunk format and the `Module.Types.Descr` term
    shape are both undocumented compiler internals. The chunk version
    (`:elixir_checker_v3` on Elixir 1.19) and `Descr` shape have changed
    every minor release. Expect breakage on upgrade.
  * **Requires `Code.compiler_options(infer_signatures: true)`** at compile
    time of the *target* module. Without it the chunk only carries function
    names, not signatures.
  * **Inference is lossy.** Most argument types come back as `dynamic` unless
    the function pattern-matches or guards on input. Returns fare better.
  * **Anything we can't translate becomes `%{kind: "dynamic"}`** rather than
    raising, so calling code can decide whether to fall back to `FromSpec`.
  """

  @doc "Returns the inferred argument and return type maps for the given MFA, or `{:error, :no_signature}` if unavailable."
  @spec fetch_signature(module(), atom(), non_neg_integer()) ::
          {:ok,
           %{args: [RpcElixir.Types.internal_spec()], return: RpcElixir.Types.internal_spec()}}
          | {:error, :no_signature}
  def fetch_signature(module, function, arity)
      when is_atom(module) and is_atom(function) and is_integer(arity) do
    with {:ok, beam_path} <- beam_path(module),
         {:ok, exports} <- read_exports(beam_path),
         {:ok, {arg_descrs, return_descr}} <- find_signature(exports, function, arity) do
      {:ok,
       %{
         args: Enum.map(arg_descrs, &descr_to_internal/1),
         return: descr_to_internal(return_descr)
       }}
    end
  end

  @doc """
  Convenience for the RPC convention `call(input, context) :: {:ok, output}`.

  Inference cannot prove an `{:error, _}` branch unless the body explicitly
  returns one, so the recovered shape is usually a single `{:ok, T}` tuple.
  Returns `{:ok, %{input: t, output: t, error: t | nil}}` when that pattern
  is recognized, else `{:error, {:invalid_return, t}}`.
  """
  @spec fetch_rpc(module(), atom()) ::
          {:ok,
           %{
             input: RpcElixir.Types.internal_spec(),
             output: RpcElixir.Types.internal_spec(),
             error: RpcElixir.Types.internal_spec() | nil
           }}
          | {:error, :no_signature}
          | {:error, {:invalid_return, RpcElixir.Types.internal_spec()}}
  def fetch_rpc(module, function) do
    with {:ok, %{args: [input, _ctx], return: return}} <-
           fetch_signature(module, function, 2) do
      case decompose_inferred_return(return) do
        {:ok, output, error} -> {:ok, %{input: input, output: output, error: error}}
        :error -> {:error, {:invalid_return, return}}
      end
    end
  end

  defp decompose_inferred_return(%{
         kind: "tuple",
         elements: [%{kind: "enum", values: ["ok"]}, payload]
       }),
       do: {:ok, payload, nil}

  defp decompose_inferred_return(%{kind: "union", variants: variants}) do
    ok_variant =
      Enum.find(variants, fn
        %{kind: "tuple", elements: [%{kind: "enum", values: ["ok"]}, _]} -> true
        _ -> false
      end)

    error_variant =
      Enum.find(variants, fn
        %{kind: "tuple", elements: [%{kind: "enum", values: ["error"]}, _]} -> true
        _ -> false
      end)

    case ok_variant do
      nil ->
        :error

      %{kind: "tuple", elements: [_, ok_payload]} ->
        error_payload =
          case error_variant do
            %{kind: "tuple", elements: [_, payload]} -> payload
            nil -> nil
          end

        {:ok, ok_payload, error_payload}
    end
  end

  defp decompose_inferred_return(_), do: :error

  defp beam_path(module) do
    case :code.which(module) do
      path when is_list(path) -> {:ok, path}
      _ -> {:error, :no_signature}
    end
  end

  defp read_exports(beam_path) do
    with {:ok, {_, [{_, chunk}]}} <- :beam_lib.chunks(beam_path, [~c"ExCk"]),
         {:elixir_checker_v3, %{exports: exports}} <- :erlang.binary_to_term(chunk) do
      {:ok, exports}
    else
      _ -> {:error, :no_signature}
    end
  end

  defp find_signature(exports, function, arity) do
    case List.keyfind(exports, {function, arity}, 0) do
      {_, %{sig: {:infer, _, [{args, return} | _]}}} -> {:ok, {args, return}}
      _ -> {:error, :no_signature}
    end
  end

  # Mirrored from Module.Types.Descr because the compiler does not expose these constants.
  @bit_binary 1
  @bit_integer 4
  @bit_float 8

  defp descr_to_internal(:term), do: %{kind: "dynamic"}
  defp descr_to_internal(%{dynamic: :term}), do: %{kind: "dynamic"}
  defp descr_to_internal(%{dynamic: inner}), do: descr_to_internal(inner)

  defp descr_to_internal(%{bitmap: bits}) when is_integer(bits), do: bitmap_to_internal(bits)

  defp descr_to_internal(%{map: {_openness, fields}}) when is_map(fields) do
    %{
      kind: "object",
      fields:
        Map.new(fields, fn {field, value_descr} ->
          {field, descr_to_internal(value_descr)}
        end)
    }
  end

  defp descr_to_internal(%{tuple: {_openness, elements}}) when is_list(elements) do
    %{kind: "tuple", elements: Enum.map(elements, &descr_to_internal/1)}
  end

  # `Descr` encodes a two-variant tuple union in BDD form. Both branches are treated as peers and joined into a union.
  defp descr_to_internal(%{tuple: {t1, :bdd_top, t2, :bdd_bot}}) do
    v1 = descr_to_internal(%{tuple: t1})
    v2 = descr_to_internal(%{tuple: t2})
    %{kind: "union", variants: [v1, v2]}
  end

  defp descr_to_internal(%{atom: {:union, set}}) do
    set |> atom_set_to_list() |> atoms_to_internal()
  end

  defp descr_to_internal(_unrecognized), do: %{kind: "dynamic"}

  defp atom_set_to_list(set) when is_map(set), do: Map.keys(set)
  defp atom_set_to_list(set) when is_list(set), do: set

  defp atoms_to_internal([]), do: %{kind: "dynamic"}
  defp atoms_to_internal(atoms), do: %{kind: "enum", values: Enum.map(atoms, &Atom.to_string/1)}

  defp bitmap_to_internal(@bit_binary), do: %{kind: "primitive", type: "string"}
  defp bitmap_to_internal(@bit_integer), do: %{kind: "primitive", type: "integer"}
  defp bitmap_to_internal(@bit_float), do: %{kind: "primitive", type: "float"}

  # integer | float collapses to float because the validator already widens integer to float.
  defp bitmap_to_internal(bits) when bits == @bit_integer + @bit_float,
    do: %{kind: "primitive", type: "float"}

  defp bitmap_to_internal(_), do: %{kind: "dynamic"}
end
