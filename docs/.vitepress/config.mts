import { defineConfig } from "vitepress";

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
      {
        text: "Reference",
        items: [
          { text: "Using the client", link: "/guide/client" },
          { text: "Codegen workflows", link: "/guide/codegen-workflow" },
          { text: "Supported types", link: "/guide/supported-types" },
          { text: "Examples", link: "/guide/examples" },
        ],
      },
    ],

    sidebar: {
      "/guide/": [
        {
          text: "Guide",
          items: [
            { text: "Getting started", link: "/guide/getting-started" },
            { text: "How it works", link: "/guide/how-it-works" },
          ],
        },
        {
          text: "Reference",
          items: [
            { text: "Using the client", link: "/guide/client" },
            { text: "Codegen workflows", link: "/guide/codegen-workflow" },
            { text: "Supported types", link: "/guide/supported-types" },
            { text: "Examples", link: "/guide/examples" },
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
      message: "Early release (0.0.1), pre-1.0. APIs may change before 1.0.",
      copyright: `<a href="${repo}">elixir-ts-rpc on GitHub</a>`,
    },
  },
});
