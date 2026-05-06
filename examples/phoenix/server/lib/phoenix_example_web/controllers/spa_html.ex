defmodule PhoenixExampleWeb.SpaHTML do
  @moduledoc """
  HTML rendering for the React SPA shell.

  This example is built to run in development via `run.sh`. When
  `:vite_dev_server` is configured (dev), `vite_assets/1` points at the running
  Vite dev server for HMR. The shell is still served by Phoenix (for the CSRF
  token) while the JS modules stream from Vite, and the `@vitejs/plugin-react`
  refresh preamble is injected here because Phoenix, not Vite, serves the HTML
  (the standard Vite "backend integration" setup).

  For a production build you would run `vite build` (which writes a hashed
  manifest into `priv/static`) and serve those assets. The `prod_assets/0` path
  reads that manifest. Wiring `vite build` into `mix assets.deploy` and
  reconciling it with `phx.digest` is left out of this example. It targets local
  development.
  """

  use PhoenixExampleWeb, :html

  alias Phoenix.HTML

  embed_templates "spa_html/*"

  @entry "src/main.tsx"

  def vite_assets(_assigns) do
    case Application.get_env(:phoenix_example, :vite_dev_server) do
      nil -> prod_assets()
      base_url -> dev_assets(String.trim_trailing(base_url, "/"))
    end
  end

  defp dev_assets(base) do
    HTML.raw("""
    <script type="module">
      import RefreshRuntime from "#{base}/@react-refresh";
      RefreshRuntime.injectIntoGlobalHook(window);
      window.$RefreshReg$ = () => {};
      window.$RefreshSig$ = () => (type) => type;
      window.__vite_plugin_react_preamble_installed__ = true;
    </script>
    <script type="module" src="#{base}/@vite/client"></script>
    <script type="module" src="#{base}/#{@entry}"></script>
    """)
  end

  defp prod_assets do
    entry =
      manifest()[@entry] ||
        raise "Vite manifest entry for #{@entry} not found. Run `vite build` before " <>
                "serving the SPA in production (or set :vite_dev_server for development)."

    css =
      entry
      |> Map.get("css", [])
      |> Enum.map_join("\n", &~s(<link rel="stylesheet" href="/#{&1}" />))

    js = ~s(<script type="module" src="/#{entry["file"]}"></script>)

    HTML.raw(css <> "\n" <> js)
  end

  defp manifest do
    path = Application.app_dir(:phoenix_example, "priv/static/.vite/manifest.json")

    case File.read(path) do
      {:ok, json} -> Phoenix.json_library().decode!(json)
      {:error, _} -> %{}
    end
  end
end
