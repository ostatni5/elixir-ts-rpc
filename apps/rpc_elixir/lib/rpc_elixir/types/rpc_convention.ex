defmodule RpcElixir.Types.RpcConvention do
  @moduledoc false

  alias RpcElixir.Types.Walker

  @spec decompose_return(Macro.t()) ::
          {:ok, {Macro.t(), Macro.t() | nil}} | {:error, :no_ok_variant}
  def decompose_return(ast) do
    ast
    |> Walker.collect_union_variants()
    # `Code.Typespec.spec_to_quoted/2` emits 2-tuples as `{:{}, _, [a, b]}` while
    # `quote do: {:ok, T}` produces a plain 2-tuple, normalize so both sources match.
    |> Enum.map(&normalize_tuple/1)
    |> Enum.reduce({nil, nil}, &accumulate_variant/2)
    |> wrap_result()
  end

  defp accumulate_variant({:ok, t}, {_output, error}), do: {t, error}
  defp accumulate_variant({:error, e}, {output, _error}), do: {output, e}
  defp accumulate_variant(_other, acc), do: acc

  defp wrap_result({nil, _}), do: {:error, :no_ok_variant}
  defp wrap_result({output, error}), do: {:ok, {output, error}}

  defp normalize_tuple({:{}, _, [a, b]}), do: {a, b}
  defp normalize_tuple(other), do: other
end
