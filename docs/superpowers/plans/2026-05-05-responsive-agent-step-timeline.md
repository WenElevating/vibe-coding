# Responsive Agent Step Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone responsive HTML prototype for collapsible agent thinking/tool/result steps inspired by the provided screenshots and restyled for this product.

**Architecture:** Create one self-contained static document under `docs/` with embedded CSS and JavaScript. The page renders both a mobile phone preview and a desktop workbench preview from shared sample step data, with collapsible rows and a desktop detail inspector.

**Tech Stack:** Plain HTML, CSS, and vanilla JavaScript. No dependencies.

---

## File Structure

- Create: `docs/responsive-agent-step-timeline.html` renders the complete prototype, embedded styles, sample data, collapse behavior, and inspector updates.
- Keep: `docs/superpowers/specs/2026-05-05-responsive-agent-step-timeline-design.md` as the approved design reference.

### Task 1: Standalone Prototype

**Files:**
- Create: `docs/responsive-agent-step-timeline.html`

- [ ] **Step 1: Create the HTML shell**

Create `docs/responsive-agent-step-timeline.html` with a complete HTML5 document, Chinese UI copy, viewport metadata, and a root app container.

- [ ] **Step 2: Add product-themed CSS tokens**

Define OKLCH-based dark neutral surfaces, one blue-green accent, semantic success/warning/error colors, system font stack, compact spacing, and responsive breakpoints.

- [ ] **Step 3: Build static mobile and desktop layout**

Add a mobile phone frame and a desktop workbench frame. Both show the same run context: workspace, adapter, safety boundary, transcript, step rows, and composer.

- [ ] **Step 4: Add collapsible step interactions**

Use vanilla JavaScript to toggle expanded rows, rotate disclosure icons, and update the desktop detail panel when a row is selected.

- [ ] **Step 5: Verify local rendering**

Run a lightweight file check and open the file locally if browser tooling is available. Expected: no missing external assets and collapsible rows work without a server.

## Self-Review

- Spec coverage: covers responsive dual layout, collapsed steps, success check icons, details, product style, context visibility, and standalone local opening.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: no external types or dependencies; IDs and data attributes stay local to the single document.
