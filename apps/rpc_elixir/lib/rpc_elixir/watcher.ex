defmodule RpcElixir.Watcher do
  @moduledoc """
  Dev-only GenServer that triggers recompilation on router source changes.

  It watches the router's own source file and every handler module's source
  file, via `RpcElixir.Router.source_files/1`. Middleware and custom-type
  modules are not watched, even though editing them changes the output.

  Requires the optional `:file_system` dep. Without it, `init/1` warns and
  returns `:ignore`. The process never starts.

  It is Phoenix-specific. Without `:endpoint` or `:on_change` there is nothing
  to do on a change. Non-Phoenix apps do not need it.
  `Mix.Tasks.Compile.ElixirTsRpc` already regenerates the client on each Elixir
  recompile.

  ## Usage

      # lib/my_app/application.ex  (Phoenix projects only)
      children = [
        {RpcElixir.Watcher, router: MyApp.Router, endpoint: MyAppWeb.Endpoint}
      ]

  ## Options

    * `:router` (required) — the RPC router module. A missing `:router` raises
      `KeyError`, even when `:file_system` is absent.
    * `:endpoint` — a Phoenix endpoint. The watcher calls
      `Phoenix.CodeReloader.reload/1` on each relevant change. That reloads
      only the endpoint's `:reloadable_compilers`, which by default excludes
      `:elixir_ts_rpc`. So add it there, or the client is not regenerated:

          reloadable_compilers: [:gettext, :elixir, :app, :elixir_ts_rpc]

      Use `:on_change` instead to call codegen directly.
    * `:on_change` — `{mod, fun, args}` invoked on change. Takes precedence
      over `:endpoint` when both are given.
    * `:debounce_ms` — coalesces rapid file events. Defaults to `200`.

  ## Restart expectations

  The linked `FileSystem` process starts inside `init/1`. The watcher traps
  exits, so a `FileSystem` crash arrives as a message rather than killing the
  watcher silently. The watcher then stops with `{:filesystem_exited, reason}`.
  The supervisor is expected to restart the pair.
  """

  use GenServer
  require Logger

  @compile {:no_warn_undefined, [FileSystem, Phoenix.CodeReloader]}

  @default_debounce_ms 200

  @doc """
  Starts the watcher and links it to the caller.

  `opts` takes the module options listed above, plus `:name`. The default name
  is `RpcElixir.Watcher`. Returns `:ignore` when `:file_system` is not loaded.
  """
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
      Logger.warning("[rpc_elixir] :file_system dep not loaded — RpcElixir.Watcher disabled")
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
    Logger.info("[rpc_elixir] source changed — invoking on_change callback")
    apply(m, f, a)
  end

  defp trigger(%{endpoint: endpoint}) when is_atom(endpoint) and not is_nil(endpoint) do
    Logger.info("[rpc_elixir] source changed — reloading via #{inspect(endpoint)}")

    if Code.ensure_loaded?(Phoenix.CodeReloader) do
      case Phoenix.CodeReloader.reload(endpoint) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("[rpc_elixir] reload failed: #{inspect(reason)}")
      end
    else
      Logger.warning("[rpc_elixir] Phoenix.CodeReloader not available — skipping reload")
    end
  end

  defp trigger(_state), do: :ok
end
