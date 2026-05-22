'use strict';

const fs = require('node:fs');
const path = require('node:path');

function toDisplayPath(rootDir, filePath) {
  return path.relative(rootDir, filePath).split(path.sep).join('/');
}

function walkMarkdownFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const entryPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkMarkdownFiles(entryPath));
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.md')) {
      files.push(entryPath);
    }
  }
  return files.sort();
}

function normalizeMarkdownTarget(target) {
  let normalized = target.trim();
  if (normalized.startsWith('<') && normalized.endsWith('>')) {
    normalized = normalized.slice(1, -1).trim();
  }
  return normalized;
}

function isExternalOrAnchor(target) {
  return /^(https?:|mailto:)/i.test(target) || target.startsWith('#');
}

function targetWithoutAnchor(target) {
  const hashIndex = target.indexOf('#');
  return hashIndex === -1 ? target : target.slice(0, hashIndex);
}

function extractMarkdownLinks(markdown) {
  const links = [];
  const linkPattern = /\[[^\]]+\]\(([^)]+)\)/g;
  for (const match of markdown.matchAll(linkPattern)) {
    links.push(normalizeMarkdownTarget(match[1]));
  }
  return links;
}

function extractSection(markdown, heading) {
  const lines = markdown.split(/\r?\n/);
  const section = [];
  let inSection = false;
  for (const line of lines) {
    if (/^##\s+/.test(line)) {
      if (inSection) break;
      inSection = line.trim().toLowerCase() === `## ${heading.toLowerCase()}`;
      continue;
    }
    if (inSection) section.push(line);
  }
  return section.join('\n');
}

function checkMarkdownLinks({ rootDir, filePath, markdown }) {
  const errors = [];
  for (const rawTarget of extractMarkdownLinks(markdown)) {
    if (isExternalOrAnchor(rawTarget)) continue;
    const target = targetWithoutAnchor(rawTarget);
    if (!target) continue;
    const resolved = path.resolve(path.dirname(filePath), target);
    if (!fs.existsSync(resolved)) {
      errors.push(
        `${toDisplayPath(rootDir, filePath)}: Missing link target ${rawTarget}`
      );
    }
  }
  return errors;
}

function checkProjectKnowledge({ rootDir = process.cwd() } = {}) {
  const knowledgeDir = path.join(rootDir, 'docs', 'project-knowledge');
  const indexPath = path.join(knowledgeDir, 'index.md');
  const errors = [];
  const notices = [];
  const checkedFiles = [];

  if (!fs.existsSync(indexPath)) {
    return {
      errors: ['docs/project-knowledge/index.md is missing'],
      notices,
      checkedFiles
    };
  }

  for (const filePath of walkMarkdownFiles(knowledgeDir)) {
    const relativePath = toDisplayPath(rootDir, filePath);
    const markdown = fs.readFileSync(filePath, 'utf8');
    checkedFiles.push(relativePath);
    errors.push(...checkMarkdownLinks({ rootDir, filePath, markdown }));

    if (!relativePath.startsWith('docs/project-knowledge/archive/') &&
        !/Last verified:\s*\S+/i.test(markdown)) {
      notices.push(`${relativePath}: Missing Last verified`);
    }
  }

  const indexMarkdown = fs.readFileSync(indexPath, 'utf8');
  const routing = extractSection(indexMarkdown, 'Routing');
  if (/\barchive\//i.test(routing)) {
    errors.push('docs/project-knowledge/index.md: Routing section links to archive');
  }

  return { errors, notices, checkedFiles };
}

function runCli() {
  const result = checkProjectKnowledge({ rootDir: process.cwd() });
  for (const notice of result.notices) {
    console.warn(`notice: ${notice}`);
  }
  for (const error of result.errors) {
    console.error(`error: ${error}`);
  }
  if (result.errors.length > 0) {
    console.error(`Project knowledge check failed with ${result.errors.length} error(s).`);
    process.exitCode = 1;
    return;
  }
  console.log(
    `Project knowledge check passed (${result.checkedFiles.length} markdown file(s), ` +
    `${result.notices.length} notice(s)).`
  );
}

if (require.main === module) {
  runCli();
}

module.exports = {
  checkProjectKnowledge
};
