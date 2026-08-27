defmodule RpcElixir.CodegenTscTest do
  @moduledoc """
  Integration test: generates TypeScript from a router, writes it to a temp
  directory alongside a minimal tsconfig.json, then runs `npx tsc --noEmit`
  to verify the output type-checks cleanly.

  Requires `npx` and TypeScript to be available; skipped otherwise.

  Run with:
      cd apps/rpc_elixir && mix test --only integration test/rpc_elixir/codegen_tsc_test.exs
  """

  use ExUnit.Case, async: false

  alias RpcElixir.JSON

  @moduletag :integration

  defmodule Paths do
    @moduledoc false

    @doc "Walks up from `dir` looking for the first ancestor containing `relative`."
    def find_up(dir, relative) do
      candidate = Path.join(dir, relative)
      parent = Path.dirname(dir)

      cond do
        File.exists?(candidate) -> candidate
        parent == dir -> nil
        true -> find_up(parent, relative)
      end
    end
  end

  @client_src Paths.find_up(__DIR__, "packages/client/src")

  @tsc_bin System.find_executable("tsc") || Paths.find_up(__DIR__, "node_modules/.bin/tsc")

  @tsc_available File.exists?(@tsc_bin) or
                   (System.find_executable("npx") != nil and
                      match?(
                        {_, 0},
                        System.cmd("npx", ["--yes=false", "tsc", "--version"],
                          stderr_to_stdout: true,
                          env: [{"npm_config_yes", "false"}]
                        )
                      ))

  setup do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("rpc_codegen_tsc_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  @tag skip: not @tsc_available
  test "generated TypeScript from basic router passes tsc --noEmit", %{tmp_dir: tmp_dir} do
    source = RpcElixir.Codegen.generate(RpcElixir.CodegenTest.Router)
    {output, exit_code} = tsc_check(source, tmp_dir)
    assert exit_code == 0, "tsc failed:\n#{output}"
  end

  @tag skip: not @tsc_available
  test "generated TypeScript with a UnixMillis wire alias passes tsc --noEmit", %{
    tmp_dir: tmp_dir
  } do
    source = RpcElixir.Codegen.generate(RpcElixir.CodegenTest.UnixMillisAliasRouter)
    {output, exit_code} = tsc_check(source, tmp_dir)
    assert exit_code == 0, "tsc failed:\n#{output}"
  end

  # A procedure whose error union mixes a domain arm and a middleware arm
  # (`DomainError<"not_found" | "unauthorized"> | MiddlewareError<"unauthorized">`)
  # is the case `source` narrowing exists for. The consumer assigns the narrowed
  # `e.code` to the source-specific literal type — it only type-checks if both a
  # `e.source === ...` check and an `isMiddlewareError` guard collapse the union
  # to the matching arm.
  @tag skip: not @tsc_available
  test "generated client narrows a mixed-source error union by source", %{tmp_dir: tmp_dir} do
    source = RpcElixir.Codegen.generate(RpcElixir.CodegenTest.MiddlewareErrorRouter)

    consumer = """
    import { isDomainError, isMiddlewareError } from "@elixir-ts-rpc/client";
    import { createRpcClient } from "./rpc.gen.ts";

    const rpc = createRpcClient({ baseUrl: "http://example.test" });

    export async function demo() {
      try {
        await rpc.users.get({ id: "1" });
      } catch (e) {
        if (!rpc.users.get.isError(e)) throw e;

        if (e.source === "domain") {
          const code: "not_found" | "unauthorized" = e.code;
          void code;
        } else if (e.source === "middleware") {
          const code: "unauthorized" = e.code;
          void code;
        }

        if (isMiddlewareError(e)) {
          const code: "unauthorized" = e.code;
          void code;
        } else if (isDomainError(e)) {
          const code: "not_found" | "unauthorized" = e.code;
          void code;
        }
      }
    }
    """

    {output, exit_code} = tsc_check(source, tmp_dir, %{"consumer.ts" => consumer})
    assert exit_code == 0, "tsc failed:\n#{output}"
  end

  defp tsc_check(source, tmp_dir, extra_files \\ %{}) do
    gen_path = Path.join(tmp_dir, "rpc.gen.ts")
    File.write!(gen_path, source)

    extra_paths =
      Enum.map(extra_files, fn {name, content} ->
        path = Path.join(tmp_dir, name)
        File.write!(path, content)
        path
      end)

    tsconfig = %{
      compilerOptions: %{
        target: "ES2022",
        module: "ES2022",
        moduleResolution: "bundler",
        lib: ["ES2022", "DOM"],
        strict: true,
        skipLibCheck: true,
        noEmit: true,
        allowImportingTsExtensions: true,
        paths: %{
          "@elixir-ts-rpc/client" => ["#{@client_src}/index.ts"]
        }
      },
      files: [gen_path | extra_paths]
    }

    tsconfig_path = Path.join(tmp_dir, "tsconfig.json")
    File.write!(tsconfig_path, JSON.encode!(tsconfig))

    if File.exists?(@tsc_bin) do
      System.cmd(@tsc_bin, ["--project", tsconfig_path], stderr_to_stdout: true, cd: tmp_dir)
    else
      System.cmd("npx", ["tsc", "--project", tsconfig_path],
        stderr_to_stdout: true,
        cd: tmp_dir
      )
    end
  end
end
