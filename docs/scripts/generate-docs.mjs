import fs from "node:fs/promises";
import path from "node:path";
import fg from "fast-glob";
import Parser from "tree-sitter";
import Luau from "tree-sitter-luau";

const scriptDir = path.dirname(new URL(import.meta.url).pathname);
const docsRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(docsRoot, "..");
const srcRoot = path.join(repoRoot, "src");
const outputRoot = path.join(docsRoot, "content", "generated");

const layerGlobs = {
  Client: "src/Client/**/*.luau",
  Server: "src/Server/**/*.luau",
  Shared: "src/Shared/**/*.luau",
  Network: "src/Network/**/*.luau",
};

const featureDefinitions = [
  {
    key: "TenantSystem",
    description: "Tenant lifecycle, offers, leases, rent, and resident interactions.",
    matcher: (relativePath) =>
      /(Tenant|Resident|Lease|Mailbox|Review|Tips|TenantHelp)/i.test(relativePath),
  },
  {
    key: "PlotSystem",
    description: "Plot ownership, build/placement, room state, and world placement.",
    matcher: (relativePath) => /(Plot|Build|Placement|Room|Grid|Floor|Wall|Roof)/i.test(relativePath),
  },
  {
    key: "Network",
    description: "Replication packets and client/server transport contracts.",
    matcher: (relativePath) =>
      relativePath.startsWith("src/Network/") || /Packets/i.test(relativePath),
  },
  {
    key: "Utilities",
    description: "Cross-cutting helpers used by multiple systems.",
    matcher: (relativePath) => /(Utilities|Helpers|Formatter|Timer|RateLimiter|Debounce)/i.test(relativePath),
  },
];

const apiScopes = [
  { key: "server-services", title: "Server Services", glob: "src/Server/Services/**/*.luau" },
  { key: "shared-utilities", title: "Shared Utilities", glob: "src/Shared/Utilities/**/*.luau" },
  { key: "client-modules", title: "Client Modules", glob: "src/Client/Modules/**/*.luau" },
];

const parser = new Parser();
parser.setLanguage(Luau);

function relPath(filePath) {
  return path.relative(repoRoot, filePath).replaceAll(path.sep, "/");
}

function normalizeWhitespace(value) {
  return value.replace(/\s+/g, " ").trim();
}

function extractBlockCommentAbove(source, functionIndex) {
  const segment = source.slice(0, functionIndex);
  const lines = segment.split("\n");
  let i = lines.length - 1;

  while (i >= 0 && lines[i].trim() === "") {
    i -= 1;
  }

  if (i < 0) {
    return "";
  }

  const blockEnd = lines[i].match(/^\s*\](=*)\]\s*$/);
  if (blockEnd) {
    const equals = blockEnd[1];
    const startPattern = new RegExp(`^\\s*--\\[${equals}\\[\\s*$`);
    const block = [];
    for (; i >= 0; i -= 1) {
      const line = lines[i];
      block.unshift(line);
      if (startPattern.test(line)) {
        const content = block
          .join("\n")
          .replace(new RegExp(`^\\s*--\\[${equals}\\[\\s*\\n?`), "")
          .replace(new RegExp(`\\n?\\s*\\]${equals}\\]\\s*$`), "");
        return content.trim();
      }
    }
    return "";
  }

  const docs = [];
  for (; i >= 0; i -= 1) {
    const line = lines[i];
    if (line.trim().startsWith("--")) {
      docs.unshift(line.replace(/^\s*--\s?/, ""));
      continue;
    }
    break;
  }
  return docs.join("\n").trim();
}

function extractExportTypes(source) {
  const results = [];
  const lines = source.split("\n");
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trimStart().startsWith("export type ")) {
      i += 1;
      continue;
    }

    const start = i;
    let end = i;
    let braceBalance = 0;
    let sawEquals = false;
    do {
      const current = lines[end] ?? "";
      for (const char of current) {
        if (char === "{") braceBalance += 1;
        if (char === "}") braceBalance -= 1;
      }
      if (current.includes("=")) {
        sawEquals = true;
      }
      if (braceBalance <= 0 && sawEquals) {
        break;
      }
      end += 1;
    } while (end < lines.length - 1);

    const snippet = lines.slice(start, end + 1).join("\n").trim();
    const nameMatch = snippet.match(/^export type\s+([A-Za-z_][A-Za-z0-9_]*)/m);
    results.push({
      name: nameMatch ? nameMatch[1] : `type_${results.length + 1}`,
      signature: snippet,
    });
    i = end + 1;
  }
  return results;
}

function extractPublicFunctions(source, moduleName) {
  const results = [];
  const pattern =
    /function\s+([A-Za-z_][A-Za-z0-9_]*)\s*([.:])\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(([\s\S]*?)\)\s*(?::\s*([^\n]+))?/g;

  for (const match of source.matchAll(pattern)) {
    const owner = match[1];
    const callStyle = match[2];
    const functionName = match[3];
    const rawParams = normalizeWhitespace(match[4] ?? "");
    const returnType = normalizeWhitespace(match[5] ?? "");
    if (owner !== moduleName) {
      continue;
    }
    const full = `function ${owner}${callStyle}${functionName}(${rawParams})${
      returnType ? `: ${returnType}` : ""
    }`;
    const doc = extractBlockCommentAbove(source, match.index ?? 0);
    results.push({
      name: functionName,
      signature: full,
      docs: doc,
    });
  }

  return results;
}

function findReturnedModuleName(source, fileBase) {
  const match = source.match(/\nreturn\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/m);
  if (match) {
    return match[1];
  }
  return fileBase.replace(/\W+/g, "_");
}

async function collectLuauFiles() {
  const files = await fg(["src/**/*.luau"], {
    cwd: repoRoot,
    absolute: true,
    onlyFiles: true,
  });
  return files.sort();
}

function classifyFeature(relativePath) {
  for (const feature of featureDefinitions) {
    if (feature.matcher(relativePath)) {
      return feature.key;
    }
  }
  return "Utilities";
}

function toDocPath(relativePath) {
  return relativePath.replace(/^src\//, "").replaceAll("/", "__").replace(/\.luau$/, "");
}

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

async function clearGeneratedDir() {
  await fs.rm(outputRoot, { recursive: true, force: true });
  await ensureDir(outputRoot);
}

async function writeFile(filePath, content) {
  await ensureDir(path.dirname(filePath));
  await fs.writeFile(filePath, content, "utf8");
}

function architectureMarkdown(filesByLayer) {
  const lines = [];
  lines.push("---");
  lines.push("title: Overview");
  lines.push("---");
  lines.push("");
  lines.push("# Architecture Overview");
  lines.push("");
  lines.push("Generated from current `src/` layout.");
  lines.push("");
  lines.push("## Runtime Boundaries");
  lines.push("");
  lines.push("```mermaid");
  lines.push("graph TD");
  lines.push("  Client[Client Runtime] -->|Packets| Network[Network Contracts]");
  lines.push("  Server[Server Runtime] -->|Packets| Network");
  lines.push("  Client --> Shared[Shared Modules]");
  lines.push("  Server --> Shared");
  lines.push("```");
  lines.push("");
  lines.push("## Layer Inventory");
  lines.push("");
  for (const [layer, files] of Object.entries(filesByLayer)) {
    lines.push(`- **${layer}**: ${files.length} Luau files`);
  }
  lines.push("");
  lines.push("## Key Roots");
  lines.push("");
  lines.push("- `src/Client/` for UI/controllers and local gameplay presentation");
  lines.push("- `src/Server/` for simulation state, services, and persistence-facing logic");
  lines.push("- `src/Shared/` for common definitions/utilities used by both runtimes");
  lines.push("- `src/Network/` for packet contracts that bridge client and server");
  return `${lines.join("\n")}\n`;
}

function featurePageMarkdown(feature, featureFiles) {
  const grouped = {
    Client: [],
    Server: [],
    Shared: [],
    Network: [],
  };
  for (const file of featureFiles) {
    const relative = relPath(file);
    const layer = relative.split("/")[1];
    if (grouped[layer]) {
      grouped[layer].push(relative);
    }
  }

  const lines = [];
  lines.push("---");
  lines.push(`title: ${feature.key}`);
  lines.push("---");
  lines.push("");
  lines.push(`# ${feature.key}`);
  lines.push("");
  lines.push(feature.description);
  lines.push("");
  lines.push(`Total files: **${featureFiles.length}**`);
  lines.push("");
  lines.push("```mermaid");
  lines.push("graph LR");
  lines.push(`  A[${feature.key}] --> C[Client]`);
  lines.push(`  A --> S[Server]`);
  lines.push(`  A --> SH[Shared]`);
  lines.push(`  A --> N[Network]`);
  lines.push("```");
  lines.push("");

  for (const layer of ["Server", "Client", "Shared", "Network"]) {
    lines.push(`## ${layer}`);
    lines.push("");
    const files = grouped[layer].sort();
    if (files.length === 0) {
      lines.push("_No files currently mapped._");
      lines.push("");
      continue;
    }
    for (const file of files) {
      lines.push(`- \`${file}\``);
    }
    lines.push("");
  }

  return `${lines.join("\n")}\n`;
}

function apiIndexMarkdown(scopePages) {
  const lines = [];
  lines.push("---");
  lines.push("title: API Index");
  lines.push("---");
  lines.push("");
  lines.push("# API Index");
  lines.push("");
  lines.push("The following pages are generated from public Luau module APIs.");
  lines.push("");
  for (const page of scopePages) {
    lines.push(`- [${page.title}](./${page.key})`);
  }
  return `${lines.join("\n")}\n`;
}

function moduleApiSection(moduleDoc) {
  const lines = [];
  lines.push(`## ${moduleDoc.moduleName}`);
  lines.push("");
  lines.push(`- Source: \`${moduleDoc.relativePath}\``);
  lines.push(`- Feature area: \`${moduleDoc.featureArea}\``);
  if (moduleDoc.astHasErrors) {
    lines.push("- Parse status: `tree-sitter parse has recoverable errors`");
  } else {
    lines.push("- Parse status: `ok`");
  }
  lines.push("");

  if (moduleDoc.exportTypes.length > 0) {
    lines.push("### Exported Types");
    lines.push("");
    for (const typeDef of moduleDoc.exportTypes) {
      lines.push(`#### ${typeDef.name}`);
      lines.push("");
      lines.push("```luau");
      lines.push(typeDef.signature);
      lines.push("```");
      lines.push("");
    }
  }

  if (moduleDoc.publicFunctions.length > 0) {
    lines.push("### Public Functions");
    lines.push("");
    for (const fn of moduleDoc.publicFunctions) {
      lines.push(`#### ${fn.name}`);
      lines.push("");
      lines.push("```luau");
      lines.push(fn.signature);
      lines.push("```");
      if (fn.docs) {
        lines.push("");
        lines.push("```text");
        lines.push(fn.docs);
        lines.push("```");
      }
      lines.push("");
    }
  } else {
    lines.push("### Public Functions");
    lines.push("");
    lines.push("_No module-scoped public functions detected._");
    lines.push("");
  }
  return lines.join("\n");
}

function scopeApiMarkdown(scope, modules) {
  const lines = [];
  lines.push("---");
  lines.push(`title: ${scope.title}`);
  lines.push("---");
  lines.push("");
  lines.push(`# ${scope.title}`);
  lines.push("");
  lines.push(`Generated modules: **${modules.length}**`);
  lines.push("");
  for (const moduleDoc of modules) {
    lines.push(moduleApiSection(moduleDoc));
  }
  return `${lines.join("\n")}\n`;
}

async function buildDocumentation() {
  await clearGeneratedDir();
  const allFiles = await collectLuauFiles();
  const filesByLayer = {
    Client: [],
    Server: [],
    Shared: [],
    Network: [],
  };

  for (const file of allFiles) {
    const relative = relPath(file);
    const layer = relative.split("/")[1];
    if (filesByLayer[layer]) {
      filesByLayer[layer].push(file);
    }
  }

  await writeFile(
    path.join(outputRoot, "architecture", "overview.md"),
    architectureMarkdown(filesByLayer),
  );

  const featureBuckets = new Map(featureDefinitions.map((feature) => [feature.key, []]));
  for (const file of allFiles) {
    const feature = classifyFeature(relPath(file));
    featureBuckets.get(feature).push(file);
  }

  for (const feature of featureDefinitions) {
    const featureFiles = featureBuckets.get(feature.key) ?? [];
    const outputPath = path.join(outputRoot, "features", `${feature.key.toLowerCase()}.md`);
    await writeFile(outputPath, featurePageMarkdown(feature, featureFiles));
  }

  const scopePages = [];
  for (const scope of apiScopes) {
    const scopeFiles = await fg([scope.glob], {
      cwd: repoRoot,
      absolute: true,
      onlyFiles: true,
    });
    const modules = [];

    for (const file of scopeFiles.sort()) {
      const source = await fs.readFile(file, "utf8");
      const tree = parser.parse(source);
      const parsedHasErrors = tree.rootNode.hasError;
      const relativePath = relPath(file);
      const moduleName = findReturnedModuleName(source, path.basename(file, ".luau"));
      const exportTypes = extractExportTypes(source);
      const publicFunctions = extractPublicFunctions(source, moduleName);
      modules.push({
        moduleName,
        relativePath,
        featureArea: classifyFeature(relativePath),
        exportTypes,
        publicFunctions,
        astHasErrors: parsedHasErrors,
      });
    }

    await writeFile(path.join(outputRoot, "api", `${scope.key}.md`), scopeApiMarkdown(scope, modules));
    scopePages.push({ key: scope.key, title: scope.title });
  }

  await writeFile(path.join(outputRoot, "api", "index.md"), apiIndexMarkdown(scopePages));
}

await buildDocumentation();
console.log("Generated docs in docs/content/generated");
