defmodule RpcElixir.Watcher do
  @moduledoc """
  Dev-only GenServer that watches every source file contributing to an RPC
  router, the router module itself and every handler module, and triggers
  recompilation when one of them changes.

  Requires the optional `:file_system` dep. If it is not loaded, `init/1`
  returns `:ignore`, the process is never started, after emitting a warning.

  This watcher is Phoenix-specific: without an `:endpoint` or `:on_change`
  option there is nothing to do when a file changes. For non-Phoenix apps the
  `Mix.Tasks.Compile.ElixirTsRpc` compiler already regenerates the TypeScript
  client on each Elixir recompile. You do not need this watcher.

  ## Usage

      # lib/my_app/application.ex  (Phoenix projects only)
      children = [
        # …
        {RpcElixir.Watcher, router: MyApp.Router, endpoint: MyAppWeb.Endpoint}
      ]

  ## Options

    * `:router` (required), the RPC router module.
    * `:endpoint`, a Phoenix endpoint. The watcher calls
      `Phoenix.CodeReloader.reload/1` on each relevant change.
    * `:on_change`, `{mod, fun, args}` invoked on change.
      Takes precedence over `:endpoint` when both are given.
    * `:debounce_ms`, milliseconds to coalesce rapid file events before
      triggering a reload. Defaults to `200`.

  ## Restart expectations

  `RpcElixir.Watcher` traps exits so that it can clean up on supervisor
  shutdown. The linked `FileSystem` process is started inside `init/1`. If it
  crashes unexpectedly the watcher will also terminate and the supervisor is
  expected to restart the pair.
  """

  use GenServer
  require Logger

  @compile {:no_warn_undefined, [FileSystem, Phoenix.CodeReloader]}

  @default_debounce_ms 200

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    router = Keyword.fetch!(opts, :router)
    endpoint = Keyword.get(opts, :endpoint)
    on_change = Keyword.get(opts, :on_change)
    debounce_ms = Keyword.get(opts, :debounce_ms, @default_debounce_ms)

    if Code.ensure_loaded?(FileSystem) do
      # Trap exits so terminate/2 runs on supervisor shutdown (see "Restart
      # expectations" in the moduledoc).
      Process.flag(:trap_exit, true)

      files = RpcElixir.Router.source_files(router) |> Enum.map(&Path.expand/1)
      dirs = files |> Enum.map(&Path.dirname/1) |> Enum.uniq()

      {:ok, pid} = FileSystem.start_link(dirs: dirs)
      FileSystem.subscribe(pid)

      Logger.info("[rpc_elixir] watching #{length(files)} source file(s) for #{inspect(router)}")

      {:ok,
       %{
         watcher_pid: pid,
         files: MapSet.new(files),
         router: router,
         endpoint: endpoint,
         on_change: on_change,
         debounce_ms: debounce_ms,
         pending_timer: nil
       }}
    else
      Logger.warning("[rpc_elixir] :file_system dep not loaded, RpcElixir.Watcher disabled")
      :ignore
    end
  end

  @impl true
  def handle_info({:file_event, pid, {path, events}}, %{watcher_pid: pid} = state) do
    if MapSet.member?(state.files, Path.expand(path)) and file_changed?(events) do
      {:noreply, schedule_trigger(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, pid, :stop}, %{watcher_pid: pid} = state) do
    {:noreply, state}
  end

  def handle_info(:debounced_trigger, state) do
    trigger(state)
    {:noreply, %{state | pending_timer: nil}}
  end

  def handle_info({:EXIT, pid, reason}, %{watcher_pid: pid} = state) do
    Logger.warning("[rpc_elixir] FileSystem watcher exited: #{inspect(reason)}")
    {:stop, {:filesystem_exited, reason}, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  defp schedule_trigger(%{pending_timer: timer, debounce_ms: debounce_ms} = state) do
    if timer, do: Process.cancel_timer(timer)
    new_timer = Process.send_after(self(), :debounced_trigger, debounce_ms)
    %{state | pending_timer: new_timer}
  end

  defp file_changed?(events) do
    Enum.any?(events, &(&1 in [:modified, :created, :renamed]))
  end

  defp trigger(%{on_change: {m, f, a}}) when is_atom(m) and is_atom(f) and is_list(a) do
    Logger.info("[rpc_elixir] source changed, invoking on_change callback")
    apply(m, f, a)
  end

  defp trigger(%{endpoint: endpoint}) when is_atom(endpoint) and not is_nil(endpoint) do
    Logger.info("[rpc_elixir] source changed, reloading via #{inspect(endpoint)}")

    if Code.ensure_loaded?(Phoenix.CodeReloader) do
      case Phoenix.CodeReloader.reload(endpoint) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("[rpc_elixir] reload failed: #{inspect(reason)}")
      end
    else
      Logger.warning("[rpc_elixir] Phoenix.CodeReloader not available, skipping reload")
    end
  end

  defp trigger(_state), do: :ok
end
