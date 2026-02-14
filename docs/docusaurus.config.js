const isGitHubActions = process.env.GITHUB_ACTIONS === "true";
const repository = process.env.GITHUB_REPOSITORY ?? "";
const [owner = "", repo = ""] = repository.split("/");
const isUserSite = repo.endsWith(".github.io");
const siteUrl =
  process.env.DOCS_SITE_URL ||
  process.env.GITHUB_PAGES_URL ||
  (owner ? `https://${owner}.github.io` : "https://example.github.io");
const baseUrl = process.env.DOCS_BASE_URL || (isGitHubActions && repo && !isUserSite ? `/${repo}/` : "/");

const config = {
  title: "Life Simulator Docs",
  tagline: "Auto-generated architecture and API reference",
  url: siteUrl,
  baseUrl,
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
