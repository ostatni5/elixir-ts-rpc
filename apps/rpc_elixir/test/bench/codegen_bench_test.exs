defmodule RpcElixir.CodegenBenchTest do
  @moduledoc """
  Benchmarks `RpcElixir.Codegen.generate/2` end-to-end across procedure
  counts of N ∈ {10, 50, 100, 250, 500, 1000}.

  Run with:
      cd apps/rpc_elixir && mix test --only bench test/bench/codegen_bench_test.exs

  Tagged `:bench` so it is excluded from normal `mix test` runs.
  """

  use ExUnit.Case, async: false

  @moduletag :bench

  @shallow_input %{
    kind: "object",
    fields: %{
      id: %{kind: "primitive", type: "string"},
      action: %{kind: "primitive", type: "string"}
    }
  }

  @shallow_output %{
    kind: "object",
    fields: %{
      ok: %{kind: "primitive", type: "boolean"},
      message: %{kind: "primitive", type: "string"}
    }
  }

  @shallow_error %{kind: "enum", values: ["not_found", "forbidden"]}

  defp deep_input(i) do
    %{
      kind: "object",
      fields: %{
        id: prim("string"),
        name: prim("string"),
        email: prim("string"),
        role: %{kind: "enum", values: ["admin", "member", "viewer"]},
        active: prim("boolean"),
        score: prim("integer"),
        metadata: %{
          kind: "object",
          fields: %{
            source: prim("string"),
            version: prim("integer"),
            tag: %{kind: "nullable", inner: prim("string")}
          }
        },
        tags: %{kind: "list", inner: prim("string")},
        index: prim("integer"),
        suffix: %{kind: "nullable", inner: prim("string")}
      },
      struct: String.to_atom("Bench.Schema.Deep#{i}")
    }
  end

  defp deep_output(i) do
    %{
      kind: "object",
      fields: %{
        id: prim("string"),
        created_at: %{kind: "datetime"},
        updated_at: %{kind: "datetime"},
        items: %{
          kind: "list",
          inner: %{
            kind: "object",
            fields: %{
              item_id: prim("string"),
              label: prim("string"),
              count: prim("integer")
            }
          }
        },
        index: prim("integer")
      },
      struct: String.to_atom("Bench.Schema.DeepOut#{i}")
    }
  end

  @deep_error %{kind: "enum", values: ["validation_failed", "unauthorized", "rate_limited"]}

  defp prim(t), do: %{kind: "primitive", type: t}

  defp build_procedures(n) do
    for i <- 1..n do
      {mod, fun, input, output, error} =
        if rem(i, 2) == 0 do
          {String.to_atom("Bench.Handlers.Shallow#{i}"), :call, @shallow_input, @shallow_output,
           @shallow_error}
        else
          {String.to_atom("Bench.Handlers.Deep#{i}"), :call, deep_input(i), deep_output(i),
           @deep_error}
        end

      %{
        name: "bench.proc_#{i}",
        handler_mod: mod,
        handler_fun: fun,
        input: input,
        output: output,
        error: error,
        middleware: [],
        doc: nil,
        schema_base: "#{inspect(mod)}.#{fun}"
      }
    end
  end

  defp make_router(procedures, mod_name) do
    escaped = Macro.escape(procedures)

    Module.create(
      mod_name,
      quote do
        def __procedures__, do: unquote(escaped)
      end,
      Macro.Env.location(__ENV__)
    )

    mod_name
  end

  @ns [10, 50, 100, 250, 500, 1000]

  defp iterations_for(n) when n >= 1000, do: {1, 3}
  defp iterations_for(_), do: {3, 10}

  @tag timeout: :infinity
  test "codegen scaling benchmark" do
    IO.puts("")
    IO.puts("  Elixir codegen benchmark - RpcElixir.Codegen.generate/2")
    IO.puts("  " <> String.duplicate("-", 62))

    IO.puts(
      "  #{String.pad_leading("N", 6)}  #{String.pad_leading("avg_ms", 10)}  #{String.pad_leading("min_ms", 10)}  #{String.pad_leading("max_ms", 10)}  #{String.pad_leading("gen_kb", 10)}"
    )

    IO.puts("  " <> String.duplicate("-", 62))

    for n <- @ns do
      procs = build_procedures(n)
      router = make_router(procs, String.to_atom("Bench.CodegenRouter.N#{n}"))
      {warmup_iterations, bench_iterations} = iterations_for(n)

      for _ <- 1..warmup_iterations//1 do
        RpcElixir.Codegen.generate(router)
      end

      {times_us, last_result} =
        Enum.map_reduce(1..bench_iterations, nil, fn _, _acc ->
          {t, result} = :timer.tc(fn -> RpcElixir.Codegen.generate(router) end)
          {t, result}
        end)

      gen_kb = byte_size(last_result) / 1024

      avg_ms = Enum.sum(times_us) / bench_iterations / 1000
      min_ms = Enum.min(times_us) / 1000
      max_ms = Enum.max(times_us) / 1000

      IO.puts(
        "  #{String.pad_leading(Integer.to_string(n), 6)}  " <>
          "#{String.pad_leading(:erlang.float_to_binary(avg_ms, decimals: 3), 10)}  " <>
          "#{String.pad_leading(:erlang.float_to_binary(min_ms, decimals: 3), 10)}  " <>
          "#{String.pad_leading(:erlang.float_to_binary(max_ms, decimals: 3), 10)}  " <>
          "#{String.pad_leading(:erlang.float_to_binary(gen_kb, decimals: 2), 10)}"
      )
    end

    IO.puts("  " <> String.duplicate("-", 62))
    IO.puts("")
  end
end
