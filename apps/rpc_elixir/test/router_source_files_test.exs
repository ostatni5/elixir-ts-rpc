defmodule RpcElixir.RouterSourceFilesTest.Router do
  use RpcElixir.Router
  alias RpcElixir.RouterFixtures.GoodHandler
  procedure "items.get", &GoodHandler.get/2
  procedure "items.list", &GoodHandler.list/2
end

defmodule RpcElixir.RouterSourceFilesTest do
  use ExUnit.Case, async: true

  alias RpcElixir.RouterFixtures.GoodHandler
  alias RpcElixir.RouterSourceFilesTest.Router

  describe "source_files/1" do
    test "includes the handler module's source path" do
      files = RpcElixir.Router.source_files(Router)
      handler_source = compiled_source(GoodHandler)

      assert handler_source in files
    end

    test "returns a deduplicated list even when multiple procedures share one handler" do
      files = RpcElixir.Router.source_files(Router)
      assert files == Enum.uniq(files)
    end

    test "all returned paths are absolute" do
      files = RpcElixir.Router.source_files(Router)
      assert files != []
      assert Enum.all?(files, &(Path.type(&1) == :absolute))
    end
  end

  defp compiled_source(mod) do
    :erlang.get_module_info(mod, :compile)[:source] |> to_string() |> Path.expand()
  end
end
