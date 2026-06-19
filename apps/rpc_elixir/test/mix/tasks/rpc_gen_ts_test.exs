defmodule Mix.Tasks.Rpc.Gen.TsTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Rpc.Gen.Ts, as: GenTsTask

  @tmp_dir System.tmp_dir!()

  defp tmp_path(filename) do
    Path.join(@tmp_dir, "rpc_gen_ts_test_#{:erlang.unique_integer([:positive])}_#{filename}")
  end

  describe "file IO" do
    test "writes TypeScript file to disk" do
      out = tmp_path("rpc.gen.ts")

      ExUnit.CaptureIO.capture_io(fn ->
        GenTsTask.run(["--router", "RpcElixir.CodegenTest.Router", "--out", out])
      end)

      assert File.exists?(out)
    end

    test "creates parent directories if they do not exist" do
      out = tmp_path("nested/dir/rpc.gen.ts")

      ExUnit.CaptureIO.capture_io(fn ->
        GenTsTask.run(["--router", "RpcElixir.CodegenTest.Router", "--out", out])
      end)

      assert File.exists?(out)
    end

    test "overwrites existing file" do
      out = tmp_path("overwrite.gen.ts")
      File.write!(out, "old content")

      ExUnit.CaptureIO.capture_io(fn ->
        GenTsTask.run(["--router", "RpcElixir.CodegenTest.Router", "--out", out])
      end)

      refute File.read!(out) =~ "old content"
    end
  end

  describe "flag parsing" do
    test "prints procedure count to stdout" do
      out = tmp_path("rpc.gen.ts")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          GenTsTask.run(["--router", "RpcElixir.CodegenTest.Router", "--out", out])
        end)

      assert output =~ "Wrote 3 procedures to #{out}"
    end

    test "respects --client-import option" do
      out = tmp_path("custom_import.gen.ts")

      ExUnit.CaptureIO.capture_io(fn ->
        GenTsTask.run([
          "--router",
          "RpcElixir.CodegenTest.Router",
          "--out",
          out,
          "--client-import",
          "@my-org/rpc-client"
        ])
      end)

      assert File.read!(out) =~ ~s(from "@my-org/rpc-client")
    end

    test "--outt (typo'd flag) raises a friendly Mix error (fix #8)" do
      out = tmp_path("typo.gen.ts")

      assert_raise Mix.Error, ~r/Usage: mix rpc\.gen\.ts/, fn ->
        GenTsTask.run(["--router", "RpcElixir.CodegenTest.Router", "--outt", out])
      end
    end
  end

  describe "error messages" do
    test "raises Mix.Error when --router is missing" do
      out = tmp_path("missing_router.gen.ts")

      assert_raise Mix.Error, ~r/--router/, fn ->
        GenTsTask.run(["--out", out])
      end
    end

    test "raises Mix.Error when --out is missing" do
      assert_raise Mix.Error, ~r/--out/, fn ->
        GenTsTask.run(["--router", "RpcElixir.CodegenTest.Router"])
      end
    end

    test "raises Mix.Error when router module cannot be compiled" do
      out = tmp_path("bad_router.gen.ts")

      assert_raise Mix.Error, ~r/could not load/, fn ->
        GenTsTask.run(["--router", "Totally.Nonexistent.RouterModule", "--out", out])
      end
    end

    test "raises Mix.Error when module is not an RPC router" do
      out = tmp_path("not_router.gen.ts")

      assert_raise Mix.Error, ~r/not an RPC router/, fn ->
        GenTsTask.run(["--router", "String", "--out", out])
      end
    end
  end
end
