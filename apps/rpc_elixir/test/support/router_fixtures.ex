defmodule RpcElixir.RouterFixtures.GoodHandler do
  @moduledoc false

  @doc "Fetch a user by id."
  @spec get(%{id: String.t()}, %{}) ::
          {:ok, %{id: String.t(), email: String.t()}} | {:error, :not_found}
  def get(_input, _ctx), do: {:ok, %{id: "1", email: "x@example.com"}}

  @spec list(%{}, %{}) :: {:ok, [%{id: String.t()}]}
  def list(_input, _ctx), do: {:ok, []}

  @doc "Update a user."
  @spec update(%{id: String.t(), email: String.t()}, %{}) ::
          {:ok, %{id: String.t()}} | {:error, :not_found}
  def update(_input, _ctx), do: {:ok, %{id: "1"}}
end

defmodule RpcElixir.RouterFixtures.ExposableHandler do
  @moduledoc false
  use RpcElixir.Handler

  @spec get(%{id: String.t()}, %{}) :: {:ok, %{id: String.t()}} | {:error, :not_found}
  def get(_input, _ctx), do: {:ok, %{id: "1"}}

  @spec list(%{}, %{}) :: {:ok, [%{id: String.t()}]}
  def list(_input, _ctx), do: {:ok, []}

  # Public arity-1 function with a spec - must be excluded from `expose`.
  @spec ping(%{}) :: :ok
  def ping(_input), do: :ok
end

defmodule RpcElixir.RouterFixtures.ArityOneOnlyHandler do
  @moduledoc false
  use RpcElixir.Handler

  @spec ping(%{}) :: :ok
  def ping(_input), do: :ok
end

defmodule RpcElixir.RouterFixtures.NoSpecHandler do
  @moduledoc false

  def get(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.RouterFixtures.BadReturnHandler do
  @moduledoc false

  @spec get(%{id: String.t()}, %{}) :: :ok
  def get(_input, _ctx), do: :ok
end

defmodule RpcElixir.RouterFixtures.WrongArityHandler do
  @moduledoc false

  @spec get(%{id: String.t()}) :: {:ok, %{}}
  def get(_input), do: {:ok, %{}}
end

defmodule RpcElixir.RouterFixtures.EchoHandler do
  @moduledoc false

  @spec echo(%{message: String.t()}, %{}) :: {:ok, %{message: String.t()}} | {:error, :noop}
  def echo(%{message: msg}, _ctx), do: {:ok, %{message: msg}}

  @spec fail(%{message: String.t()}, %{}) :: {:ok, %{message: String.t()}} | {:error, :always}
  def fail(_input, _ctx), do: {:error, :always}

  @spec bad_output(%{message: String.t()}, %{}) ::
          {:ok, %{message: String.t()}} | {:error, :noop}
  def bad_output(_input, _ctx), do: {:ok, %{not_message: 42}}

  @spec always_raise(%{message: String.t()}, %{}) :: {:ok, %{message: String.t()}}
  def always_raise(_input, _ctx), do: raise(RuntimeError, "intentional test exception")

  @spec rpc_error(%{message: String.t()}, %{}) ::
          {:ok, %{message: String.t()}} | {:error, :custom}
  def rpc_error(_input, _ctx),
    do: {:error, %RpcElixir.RpcError{code: :custom, message: "boom"}}
end

defmodule RpcElixir.RouterFixtures.FakeStruct do
  @moduledoc false
  defstruct [:code]
end

defmodule RpcElixir.RouterFixtures.StructErrorHandler do
  @moduledoc false

  alias RpcElixir.RouterFixtures.FakeStruct

  @spec map_error(%{message: String.t()}, %{}) ::
          {:ok, %{message: String.t()}} | {:error, :email_taken}
  def map_error(_input, _ctx), do: {:error, %{code: :email_taken}}

  @spec struct_error(%{message: String.t()}, %{}) ::
          {:ok, %{message: String.t()}} | {:error, :noop}
  def struct_error(_input, _ctx), do: {:error, %FakeStruct{code: :some_code}}

  @spec not_found(%{}, %{}) :: {:ok, %{}} | {:error, :not_found}
  def not_found(_input, _ctx), do: {:error, :not_found}

  @spec forbidden(%{}, %{}) :: {:ok, %{}} | {:error, :forbidden}
  def forbidden(_input, _ctx), do: {:error, :forbidden}
end

defmodule RpcElixir.RouterFixtures.HaltingMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware
  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, opts) do
    Resolution.halt(res, Keyword.get(opts, :reason, :halted_by_test))
  end
end

defmodule RpcElixir.RouterFixtures.TraceMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware
  alias RpcElixir.Resolution

  @impl true
  def call(%Resolution{} = res, opts) do
    tag = Keyword.fetch!(opts, :tag)
    trace = Map.get(res.private, :trace, [])
    Resolution.put_private(res, :trace, trace ++ [tag])
  end
end
