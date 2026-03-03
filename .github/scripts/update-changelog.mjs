import fs from "node:fs";

const changelogPath = "CHANGELOG.md";
const eventPath = process.env.GITHUB_EVENT_PATH;

if (!eventPath) {
  console.error("GITHUB_EVENT_PATH is not set.");
  process.exit(1);
}

const event = JSON.parse(fs.readFileSync(eventPath, "utf8"));
const pr = event.pull_request;

if (!pr || !pr.merged) {
  console.log("No merged pull request in this event. Nothing to update.");
  process.exit(0);
}

const number = pr.number;
const title = String(pr.title || "Untitled PR").trim();
const author = pr.user?.login || "unknown";
const authorUrl = pr.user?.html_url || `https://github.com/${author}`;
const prUrl = pr.html_url || "";
const mergedDate = (pr.merged_at || new Date().toISOString()).slice(0, 10);
const labels = (pr.labels || [])
  .map((label) => label?.name)
  .filter(Boolean)
  .sort((a, b) => a.localeCompare(b));
const labelsText = labels.length > 0 ? `, labels: ${labels.join(", ")}` : "";
const entry = `- PR #${number}: ${title} ([@${author}](${authorUrl}), ${mergedDate}${labelsText}) ([link](${prUrl}))`;
const marker = `PR #${number}:`;

let changelog = fs.readFileSync(changelogPath, "utf8");

if (changelog.includes(marker)) {
  console.log(`CHANGELOG already contains PR #${number}.`);
  process.exit(0);
}

if (!changelog.includes("## [Unreleased]")) {
  changelog = `## [Unreleased]\n\n${changelog}`;
}

const unreleasedMatch = changelog.match(/^## \[Unreleased\][\s\S]*?(?=^## \[|$)/m);
if (!unreleasedMatch || unreleasedMatch.index === undefined) {
  console.error("Could not locate the [Unreleased] section in CHANGELOG.md.");
  process.exit(1);
}

const blockStart = unreleasedMatch.index;
const blockEnd = blockStart + unreleasedMatch[0].length;
const unreleasedBlock = unreleasedMatch[0];

let updatedBlock;
const mergedHeading = "### Merged PRs";
if (unreleasedBlock.includes(mergedHeading)) {
  updatedBlock = unreleasedBlock.replace(
    /### Merged PRs\n\n/,
    `### Merged PRs\n\n${entry}\n`
  );
} else {
  updatedBlock = `${unreleasedBlock}\n${mergedHeading}\n\n${entry}\n`;
}

const updated = `${changelog.slice(0, blockStart)}${updatedBlock}${changelog.slice(blockEnd)}`;
fs.writeFileSync(changelogPath, updated);
console.log(`Added changelog entry for PR #${number}.`);
