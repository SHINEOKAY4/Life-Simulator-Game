const config = {
  title: "Life Simulator Docs",
  tagline: "Auto-generated architecture and API reference",
  url: "https://example.github.io",
  baseUrl: "/",
  onBrokenLinks: "throw",
  i18n: {
    defaultLocale: "en",
    locales: ["en"],
  },
  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: "warn",
    },
  },
  themes: ["@docusaurus/theme-mermaid"],
  presets: [
    [
      "classic",
      {
        docs: {
          path: "content",
          routeBasePath: "/",
          sidebarPath: "./sidebars.js",
        },
        blog: false,
        pages: false,
        theme: {
          customCss: "./src/css/custom.css",
        },
      },
    ],
  ],
  themeConfig: {
    navbar: {
      title: "Life Simulator Docs",
      items: [
        { to: "/intro", label: "Docs", position: "left" },
        { to: "/generated/architecture/overview", label: "Architecture", position: "left" },
        { to: "/generated/api", label: "API", position: "left" },
      ],
    },
    docs: {
      sidebar: {
        hideable: true,
      },
    },
    colorMode: {
      defaultMode: "light",
      disableSwitch: false,
      respectPrefersColorScheme: true,
    },
  },
};

module.exports = config;
