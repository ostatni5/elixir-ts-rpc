defmodule RpcElixir.Plug do
  @moduledoc """
  HTTP transport adapter for `RpcElixir`, implemented as a `Plug`.

  It mounts a router at a path prefix. It decodes JSON bodies and dispatches to
  the procedure pipeline. It drains response cookies and headers onto the conn,
  then renders JSON. See [Getting started](getting-started.md) for the mounting
  walkthrough.

  ## Options

    * `:router` (required) — a module using `RpcElixir.Router`.
    * `:path_prefix` (optional, default `"/rpc"`) — stripped from the request
      path before dispatch. `POST /rpc/users.get` dispatches `"users.get"`.
    * `:ctx_builder` (optional) — `(Plug.Conn.t() -> RpcElixir.Context.t())`.
      Its result is the base context. The transport always overwrites `:req`
      with conn-derived metadata (cookies, headers, remote_ip, session). Those
      fields are always present, whatever the builder returns.
    * `:max_body_size` (optional, default 8 MB) — request body cap in bytes.
      Larger bodies are rejected with 413 `:payload_too_large`.
    * `:max_body_depth` (optional, default 64) — nesting-depth cap on the
      decoded JSON body. Deeper payloads are rejected with 400
      `:input_validation_failed`, before validation runs. This bounds stack and
      CPU use that the byte cap alone cannot.
    * `:require_content_type` (optional, default `true`) — the request must
      carry `content-type: application/json`. A charset and other params are
      allowed. Other types are rejected with 415 `:unsupported_media_type`.
      See `## Security / CSRF`.
    * `:allowed_origins` (optional, default `nil` = disabled) — allow-list of
      origin strings. An `origin` header outside the list is rejected with 403
      `:forbidden`. See `## Security / CSRF`.

  ## Security / CSRF

  This adapter dispatches state-changing RPC over `POST`. It can pair with
  cookie-based sessions (see `## Session integration`). That combination is a
  CSRF surface. A cross-site page can auto-submit a form to an RPC endpoint.
  The browser then attaches the session cookie. Undefended, that lets an
  attacker trigger authenticated calls. Two mitigations are enforced here:

    * **Content-Type enforcement** (`:require_content_type`, default `true`).
      Requiring `application/json` stops the request being a "simple"
      cross-site request. Browsers must then send a CORS preflight, which the
      server never approves. HTML forms can only send
      `application/x-www-form-urlencoded`, `multipart/form-data`, or
      `text/plain`. They are blocked outright. This is the primary CSRF defense.
    * **Origin allow-listing** (`:allowed_origins`, default disabled). When
      configured, a present but non-allow-listed `origin` is rejected with 403.
      This is defense-in-depth for browsers that send `Origin` on
      state-changing requests.

  The bundled JS client always sends `Content-Type: application/json`. So the
  default-on enforcement does not break legitimate use.

  ## Session integration

  Configure `Plug.Session` earlier in your pipeline. The adapter reads it into
  `ctx.req.session`. It drains `Resolution.resp_session` back after dispatch.

      defmodule MyApp.Router do
        use Plug.Builder

        plug Plug.Session,
          store: :cookie, key: "_my_app_session", signing_salt: "my_salt"

        plug :fetch_session
        plug RpcElixir.Plug, router: MyApp.RpcRouter
      end

  In middleware, use `Resolution.put_session/3`, `delete_session/2`, or
  `clear_session/1` to change the session. Read it via `res.ctx.req[:session]`.

  ## Response draining order

  After dispatch, session mutations, cookies, and headers are applied to the
  conn first. The response body is written only after that. Plug requires this
  order: session and cookie mutations must precede the response.
  """

  @behaviour Plug

  require Logger

  import Plug.Conn

  alias RpcElixir.{Context, Dispatcher, JSON, Resolution, RpcError}

  @default_max_body_size 8 * 1024 * 1024
  # Read in 1 MB chunks rather than one slurp to avoid memory spikes.
  @read_chunk_size 1024 * 1024
  # The byte cap bounds payload size but not nesting; a deeply-nested JSON
  # document can still exhaust the stack during recursive validation. Reject
  # anything past this structural depth right after decode.
  @default_max_body_depth 64

  @impl Plug
  def init(opts) do
    router = Keyword.fetch!(opts, :router)
    path_prefix = Keyword.get(opts, :path_prefix, "/rpc")
    ctx_builder = Keyword.get(opts, :ctx_builder, nil)
    max_body_size = Keyword.get(opts, :max_body_size, @default_max_body_size)
    max_body_depth = Keyword.get(opts, :max_body_depth, @default_max_body_depth)
    require_content_type = Keyword.get(opts, :require_content_type, true)
    allowed_origins = Keyword.get(opts, :allowed_origins, nil)

    %{
      router: router,
      path_prefix: path_prefix,
      ctx_builder: ctx_builder,
      max_body_size: max_body_size,
      max_body_depth: max_body_depth,
      require_content_type: require_content_type,
      allowed_origins: allowed_origins
    }
  end

  @impl Plug
  def call(%Plug.Conn{method: "POST"} = conn, %{path_prefix: prefix} = opts) do
    case strip_prefix(conn.request_path, prefix) do
      {:ok, procedure} -> dispatch(conn, procedure, opts)
      :error -> not_found(conn)
    end
  end

  def call(conn, _opts), do: not_found(conn)

  defp strip_prefix(path, prefix) do
    prefix_with_slash = prefix <> "/"

    if String.starts_with?(path, prefix_with_slash) do
      procedure = String.slice(path, String.length(prefix_with_slash)..-1//1)

      if procedure == "" do
        :error
      else
        {:ok, procedure}
      end
    else
      :error
    end
  end

  defp dispatch(conn, procedure, %{
         router: router,
         ctx_builder: ctx_builder,
         max_body_size: max_body_size,
         max_body_depth: max_body_depth,
         require_content_type: require_content_type,
         allowed_origins: allowed_origins
       }) do
    conn = fetch_cookies(conn)

    with :ok <- check_origin(conn, allowed_origins),
         :ok <- check_content_type(conn, require_content_type),
         {:ok, body, conn} <- read_body_capped(conn, max_body_size),
         {:ok, input} <- decode_body(body, max_body_depth) do
      ctx = build_ctx(conn, procedure, ctx_builder)

      resolution =
        Dispatcher.dispatch(router, procedure, input, %Resolution{procedure: procedure, ctx: ctx})

      send_resolution(conn, resolution)
    else
      {:error, :forbidden_origin} ->
        send_framework_error(
          conn,
          :forbidden,
          "request origin is not allowed",
          %{reason: "forbidden_origin"}
        )

      {:error, :unsupported_media_type} ->
        send_framework_error(
          conn,
          :unsupported_media_type,
          "content-type must be application/json",
          %{reason: "unsupported_media_type"}
        )

      {:error, :payload_too_large} ->
        send_framework_error(
          conn,
          :payload_too_large,
          "request body exceeds size limit",
          %{reason: "body_too_large"}
        )

      {:error, :invalid_json} ->
        send_framework_error(
          conn,
          :input_validation_failed,
          "request body is not valid JSON",
          %{reason: "invalid_json"}
        )

      {:error, :body_too_deep} ->
        send_framework_error(
          conn,
          :input_validation_failed,
          "request body nesting exceeds the allowed depth",
          %{reason: "body_too_deep"}
        )

      {:error, reason} ->
        send_framework_error(
          conn,
          :handler_error,
          "failed to read request body",
          read_body_error_details(reason)
        )
    end
  end

  defp read_body_error_details(reason) do
    if expose_error_details?(), do: %{reason: inspect(reason)}, else: %{}
  end

  defp expose_error_details? do
    Application.get_env(:elixir_ts_rpc, :expose_error_details, false)
  end

  defp send_framework_error(conn, code, message, details) do
    err = RpcError.framework(code, message, details)
    send_error(conn, err.status, err)
  end

  defp read_body_capped(conn, max_bytes) do
    read_body_capped(conn, max_bytes, [])
  end

  defp read_body_capped(conn, remaining, acc) do
    case read_body(conn, length: min(remaining, @read_chunk_size)) do
      # The adapter may overshoot `:length` and return the whole body in one
      # `{:ok, ...}` (Cowboy reads up to its `read_length`), so the cap is
      # enforced here too, not only on the `{:more, ...}` path.
      {:ok, chunk, _conn} when byte_size(chunk) > remaining ->
        {:error, :payload_too_large}

      {:ok, chunk, conn} ->
        {:ok, IO.iodata_to_binary([acc, chunk]), conn}

      {:more, chunk, conn} ->
        case remaining - byte_size(chunk) do
          left when left > 0 -> read_body_capped(conn, left, [acc, chunk])
          _ -> {:error, :payload_too_large}
        end

      {:error, _reason} = err ->
        err
    end
  end

  defp check_origin(_conn, nil), do: :ok

  defp check_origin(conn, allowed_origins) when is_list(allowed_origins) do
    case get_req_header(conn, "origin") do
      [] -> :ok
      [origin | _] -> if origin in allowed_origins, do: :ok, else: {:error, :forbidden_origin}
    end
  end

  defp check_content_type(_conn, false), do: :ok

  defp check_content_type(conn, true) do
    case get_req_header(conn, "content-type") do
      [content_type | _] ->
        if json_content_type?(content_type), do: :ok, else: {:error, :unsupported_media_type}

      [] ->
        {:error, :unsupported_media_type}
    end
  end

  # Accepts "application/json" with optional parameters (e.g. charset),
  # case-insensitively per RFC 7231.
  defp json_content_type?(content_type) do
    media_type =
      content_type
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim()
      |> String.downcase()

    media_type == "application/json"
  end

  defp decode_body("", _max_depth), do: {:ok, %{}}

  defp decode_body(body, max_depth) do
    case JSON.decode(body) do
      {:ok, map} when is_map(map) -> enforce_depth(map, max_depth)
      {:ok, _} -> {:error, :invalid_json}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp enforce_depth(term, max_depth) do
    if within_depth?(term, max_depth), do: {:ok, term}, else: {:error, :body_too_deep}
  end

  defp within_depth?(_term, remaining) when remaining < 0, do: false

  defp within_depth?(map, remaining) when is_map(map) do
    Enum.all?(map, fn {_k, v} -> within_depth?(v, remaining - 1) end)
  end

  defp within_depth?(list, remaining) when is_list(list) do
    Enum.all?(list, &within_depth?(&1, remaining - 1))
  end

  defp within_depth?(_scalar, _remaining), do: true

  defp build_ctx(conn, _procedure, ctx_builder) do
    base_ctx =
      if ctx_builder do
        ctx_builder.(conn)
      else
        %Context{}
      end

    req = %{
      cookies: conn.req_cookies,
      headers: conn.req_headers,
      remote_ip: conn.remote_ip,
      method: conn.method,
      path: conn.request_path,
      session: read_session(conn)
    }

    %{base_ctx | req: req}
  end

  # Normalizes the unfetched-session case to an empty map so middleware doing
  # `session[:x]` never crashes on nil when Plug.Session isn't configured.
  defp read_session(conn) do
    get_session(conn)
  rescue
    ArgumentError -> %{}
  end

  defp send_resolution(conn, %Resolution{result: result} = resolution) do
    conn
    |> drain_resp_headers(resolution.resp_headers)
    |> drain_resp_cookies(resolution.resp_cookies)
    |> drain_resp_session(resolution)
    |> render_result(result)
  end

  defp drain_resp_headers(conn, []), do: conn
  defp drain_resp_headers(conn, headers), do: prepend_resp_headers(conn, headers)

  defp drain_resp_cookies(conn, cookies) when map_size(cookies) == 0, do: conn

  defp drain_resp_cookies(conn, cookies) do
    Enum.reduce(cookies, conn, fn
      {name, {:delete, opts}}, acc -> delete_resp_cookie(acc, name, opts)
      {name, {value, opts}}, acc -> put_resp_cookie(acc, name, value, opts)
    end)
  end

  defp drain_resp_session(conn, %Resolution{resp_session_clear: false, resp_session: session})
       when map_size(session) == 0,
       do: conn

  defp drain_resp_session(conn, %Resolution{} = resolution) do
    apply_session_changes(conn, resolution)
  rescue
    _ ->
      Logger.warning("RpcElixir.Plug: resp_session set but Plug.Session not configured")
      conn
  end

  defp apply_session_changes(conn, %Resolution{resp_session_clear: true}) do
    clear_session(conn)
  end

  defp apply_session_changes(conn, %Resolution{resp_session: session}) do
    Enum.reduce(session, conn, fn
      {key, :delete}, acc -> delete_session(acc, key)
      {key, value}, acc -> put_session(acc, key, value)
    end)
  end

  defp render_result(conn, {:ok, serialized}) do
    body = JSON.encode!(%{ok: serialized})
    send_json(conn, 200, body)
  end

  defp render_result(conn, {:error, %RpcError{} = err}) do
    status = err.status || status_for_code(err.code, err.details)
    send_error(conn, status, err)
  end

  defp not_found(conn) do
    err =
      RpcError.framework(
        :procedure_not_found,
        "no procedure found at #{conn.method} #{conn.request_path}"
      )

    send_error(conn, err.status, err)
  end

  defp send_error(conn, status, %RpcError{} = err) do
    error_map =
      %{code: err.code}
      |> maybe_put(:source, err.source)
      |> maybe_put(:message, err.message)
      |> maybe_put(:details, err.details)

    body = JSON.encode!(%{error: error_map})
    send_json(conn, status, body)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, details) when is_map(details) and map_size(details) == 0, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  # Framework codes resolve via the shared map on RpcError (single source of
  # truth). `:not_found` is a conventional user-defined typed code that the
  # transport maps to 404; everything else defaults to 400.
  defp status_for_code(code, _details) do
    cond do
      status = RpcError.status_for(code) -> status
      code == :not_found -> 404
      true -> 400
    end
  end
end
