import { readFileSync } from "node:fs";
import { transformerTwoslash } from "@shikijs/vitepress-twoslash";
import ts from "typescript";
import { defineConfig } from "vitepress";

// Twoslash type-checks every ` ```ts twoslash ` block against the real generated
// client and fails the build on error, so a doc snippet cannot drift from what
// codegen emits. These two files are mounted as virtual modules under the names
// a real app would use, letting snippets `import ... from "./rpc.gen"` verbatim.
// Read as text, never imported, so esbuild does not try to bundle them.
const virtualFile = (name: string) =>
  readFileSync(new URL(`./twoslash/${name}`, import.meta.url), "utf8");

const twoslash = transformerTwoslash({
  twoslashOptions: {
    compilerOptions: {
      target: ts.ScriptTarget.ESNext,
      module: ts.ModuleKind.ESNext,
      moduleResolution: ts.ModuleResolutionKind.Bundler,
      jsx: ts.JsxEmit.ReactJSX,
      lib: ["lib.esnext.d.ts", "lib.dom.d.ts"],
      strict: true,
      skipLibCheck: true,
      // Keep ambient @types out of the snippet scope: a stray global would let a
      // broken snippet type-check for the wrong reason.
      types: [],
    },
    extraFiles: {
      "rpc.gen.ts": virtualFile("rpc.generated.ts"),
      "rpc.ts": virtualFile("rpc-react.ts"),
    },
  },
});

const repo = "https://github.com/ostatni5/elixir-ts-rpc";

// Served from https://ostatni5.github.io/elixir-ts-rpc/, so every asset and
// link must be prefixed with the repo name. Change this if the repo is renamed
// or moved to a custom domain (then base becomes "/").
export default defineConfig({
  title: "elixir-ts-rpc",
  description:
    "Typed RPC between Elixir servers and TypeScript clients, driven by ordinary @spec typespecs.",
  base: "/elixir-ts-rpc/",
  lang: "en-US",
  cleanUrls: true,
  lastUpdated: true,

  markdown: {
    codeTransformers: [twoslash],
  },

  vite: {
    optimizeDeps: { include: ["@shikijs/vitepress-twoslash/client"] },
    ssr: { noExternal: ["@shikijs/vitepress-twoslash"] },
  },

  head: [
    ["meta", { name: "theme-color", content: "#7c3aed" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:title", content: "elixir-ts-rpc" }],
    [
      "meta",
      {
        property: "og:description",
        content: "Typed RPC between Elixir and TypeScript, from your @spec typespecs.",
      },
    ],
  ],

  themeConfig: {
    nav: [
      { text: "Guide", link: "/guide/getting-started" },
      { text: "Comparison", link: "/guide/comparison" },
      { text: "Playground", link: "https://elixir-ts-rpc-playground.netlify.app" },
      {
        text: "Reference",
        items: [
          {
            text: "Server",
            items: [
              { text: "Plug options", link: "/guide/plug-options" },
              { text: "Writing middleware", link: "/guide/middleware" },
              { text: "Supported types", link: "/guide/supported-types" },
              { text: "Custom types", link: "/guide/custom-types" },
              { text: "Handling errors", link: "/guide/errors" },
            ],
          },
          {
            text: "Client",
            items: [
              { text: "Using the client", link: "/guide/client" },
              { text: "React + TanStack Query", link: "/guide/react" },
            ],
          },
          {
            text: "Workflow",
            items: [
              { text: "Codegen workflows", link: "/guide/codegen-workflow" },
              { text: "Examples", link: "/guide/examples" },
            ],
          },
        ],
      },
      { text: "Elixir API (HexDocs)", link: "https://hexdocs.pm/elixir_ts_rpc" },
    ],

    sidebar: {
      "/guide/": [
        {
          text: "Guide",
          items: [
            { text: "Getting started", link: "/guide/getting-started" },
            { text: "How it works", link: "/guide/how-it-works" },
            { text: "Comparison", link: "/guide/comparison" },
          ],
        },
        {
          text: "Server",
          items: [
            { text: "Plug options", link: "/guide/plug-options" },
            { text: "Writing middleware", link: "/guide/middleware" },
            { text: "Supported types", link: "/guide/supported-types" },
            { text: "Custom types", link: "/guide/custom-types" },
            { text: "Handling errors", link: "/guide/errors" },
          ],
        },
        {
          text: "Client",
          items: [
            { text: "Using the client", link: "/guide/client" },
            { text: "React + TanStack Query", link: "/guide/react" },
          ],
        },
        {
          text: "Workflow",
          items: [
            { text: "Codegen workflows", link: "/guide/codegen-workflow" },
            { text: "Examples", link: "/guide/examples" },
            {
              text: "Elixir API (HexDocs)",
              link: "https://hexdocs.pm/elixir_ts_rpc",
            },
          ],
        },
      ],
    },

    socialLinks: [{ icon: "github", link: repo }],

    editLink: {
      pattern: `${repo}/edit/main/docs/:path`,
      text: "Edit this page on GitHub",
    },

    search: { provider: "local" },

    footer: {
      message: "Early release (0.0.1), pre-1.0 — APIs may change before 1.0.",
      copyright: `<a href="${repo}">elixir-ts-rpc on GitHub</a>`,
    },
  },
});
