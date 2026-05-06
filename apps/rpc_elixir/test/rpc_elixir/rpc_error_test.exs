defmodule RpcElixir.RpcErrorTest do
  use ExUnit.Case, async: true

  alias RpcElixir.RpcError

  describe "framework_errors/0 and status_for/1" do
    test "every framework code resolves to its mapped status" do
      for {code, status} <- RpcError.framework_errors() do
        assert RpcError.status_for(code) == status
      end
    end

    test "non-framework codes resolve to nil (transport applies the generic default)" do
      assert RpcError.status_for(:not_found) == nil
      assert RpcError.status_for(:email_taken) == nil
    end

    test "current framework status mapping is preserved" do
      assert RpcError.framework_errors() == %{
               procedure_not_found: 404,
               input_validation_failed: 400,
               output_validation_failed: 500,
               handler_error: 500,
               middleware_halted: 500,
               unauthorized: 401,
               forbidden: 403,
               payload_too_large: 413,
               unsupported_media_type: 415
             }
    end
  end

  describe "framework/3" do
    test "stamps the default status for the code" do
      err = RpcError.framework(:procedure_not_found, "nope")

      assert %RpcError{code: :procedure_not_found, message: "nope", details: nil, status: 404} =
               err
    end

    test "carries details through" do
      err = RpcError.framework(:input_validation_failed, "bad", %{field: "id"})
      assert err.status == 400
      assert err.details == %{field: "id"}
    end

    test "raises for an unknown (non-framework) code" do
      assert_raise FunctionClauseError, fn -> RpcError.framework(:totally_unknown, "x") end
    end
  end
end
