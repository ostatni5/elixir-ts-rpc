defmodule RpcElixir.Types.FromInferredTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Types.FromInferred
  alias RpcElixir.TypespecFixtures.Inferred

  describe "fetch_signature/3" do
    test "recovers open-map field shapes from pattern-matched args" do
      assert {:ok, %{args: [input, ctx], return: return}} =
               FromInferred.fetch_signature(Inferred, :get_user, 2)

      assert input == %{kind: "object", fields: %{id: %{kind: "dynamic"}}}
      assert ctx == %{kind: "dynamic"}
      assert match?(%{kind: "tuple"}, return)
    end

    test "recovers open-map field shape for parameterized-style handler" do
      assert {:ok, %{args: [input, _ctx]}} =
               FromInferred.fetch_signature(Inferred, :list_users, 2)

      assert input == %{kind: "object", fields: %{limit: %{kind: "dynamic"}}}
    end

    test "guarded binary arg is not narrowed by inference (lossy vs FromSpec)" do
      assert {:ok, %{args: [a, _ctx], return: return}} =
               FromInferred.fetch_signature(Inferred, :echo, 2)

      assert a == %{kind: "dynamic"}
      assert match?(%{kind: "tuple"}, return)
    end

    test "returns :no_signature when the function does not exist" do
      assert {:error, :no_signature} = FromInferred.fetch_signature(Inferred, :missing, 2)
    end
  end

  describe "fetch_rpc/2" do
    test "extracts input/output from an inferred {:ok, _} return" do
      assert {:ok, %{input: input, output: output, error: nil}} =
               FromInferred.fetch_rpc(Inferred, :get_user)

      assert input == %{kind: "object", fields: %{id: %{kind: "dynamic"}}}

      assert output == %{
               kind: "object",
               fields: %{
                 id: %{kind: "dynamic"},
                 name: %{kind: "primitive", type: "string"}
               }
             }
    end

    test "error is nil when only an {:ok, _} branch was inferred" do
      assert {:ok, %{error: nil}} = FromInferred.fetch_rpc(Inferred, :list_users)
    end

    test "succeeds without @spec - inference is the source" do
      assert {:ok, %{error: nil}} = FromInferred.fetch_rpc(Inferred, :no_spec)
    end

    test "decomposes {:ok, map} | {:error, atom} union from BDD-encoded return" do
      assert {:ok, %{input: input, output: output, error: error}} =
               FromInferred.fetch_rpc(Inferred, :find_user)

      assert input == %{kind: "object", fields: %{id: %{kind: "dynamic"}}}

      assert output == %{
               kind: "object",
               fields: %{
                 id: %{kind: "dynamic"},
                 name: %{kind: "primitive", type: "string"}
               }
             }

      assert error == %{kind: "enum", values: ["not_found"]}
    end

    test "helper return type propagates into calling handler via inference" do
      # wrapped_get delegates to find_user, which calls the private build_user helper.
      # The inferred output/error shapes must match the concrete shapes produced by build_user.
      assert {:ok, %{input: input, output: output, error: error}} =
               FromInferred.fetch_rpc(Inferred, :wrapped_get)

      # wrapped_get passes params through without pattern-matching, so input is unnarrowed
      assert input == %{kind: "dynamic"}

      assert output == %{
               kind: "object",
               fields: %{
                 id: %{kind: "dynamic"},
                 name: %{kind: "primitive", type: "string"}
               }
             }

      assert error == %{kind: "enum", values: ["not_found"]}
    end

    test "tagged_status: multi-clause handler, only first clause survives find_signature" do
      # Inference takes the first clause: {:ok, s} where s is unnarrowed (:term → dynamic).
      # The {:error, :unknown} branch from the second clause is lost.
      assert {:ok, %{input: input, output: output, error: nil}} =
               FromInferred.fetch_rpc(Inferred, :tagged_status)

      assert input == %{kind: "object", fields: %{status: %{kind: "dynamic"}}}
      assert output == %{kind: "dynamic"}
    end
  end
end
