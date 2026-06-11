# Responsive Agent Step Timeline Design

## Problem

The current conversation UI needs a clearer way to show agent progress without flooding the transcript. The user likes the reference pattern where thinking and tool calls collapse into compact rows, and completed rows switch to a check icon. The new design should borrow that interaction, but express it through this product's calm, technical, trustworthy control-plane style.

## Decision

Use one responsive webpage prototype that shows the same conversation state in two layouts:

- Mobile: a phone-width transcript where assistant messages contain collapsible thinking, tool, and result steps inline.
- Desktop: a workbench layout with the transcript on the left and a persistent details panel on the right.

The prototype should not copy the reference visuals directly. It should keep the step folding, success iconography, and details affordance while using restrained product colors, dense but readable spacing, and explicit execution context.

## Visual Direction

Physical scene: a developer checks an active CLI run on a phone during a short break, then opens the same run on a desktop monitor in a dim workspace to inspect the exact command output.

Theme: dark-neutral, because the product is used beside coding tools for long sessions and should reduce glare while keeping state text legible.

Color strategy: restrained. Use tinted neutral surfaces, one blue-green accent for active/selected state, and semantic success/warning/error only when status needs it.

## Interaction Model

Each assistant progress unit is a step row with:

- A leading state glyph: pending dot, active spinner/ring, success check, warning marker, or blocked marker.
- A short title that remains useful while collapsed.
- Secondary metadata such as adapter, elapsed time, workspace, or command count.
- A disclosure control for inline expansion.
- Optional details shown in the desktop inspector when selected.

Collapsed rows should communicate progress at a glance. Expanded rows should reveal the minimum useful context: prompt/question asked, command executed, file touched, output summary, and approval state.

## Responsive Behavior

Mobile uses a single column:

- Header shows workspace, adapter, pairing/safety status, and conversation title.
- Transcript remains primary.
- Expanded details appear inline below the selected step.
- Bottom composer stays visually quiet and reachable.

Desktop uses a two-pane workbench:

- Left pane shows the same transcript and step rows.
- Right pane shows selected step details with structured fields.
- Header keeps workspace and execution context visible before any action.

## Components

- `RunHeader`: title, workspace, adapter, status, and safety badges.
- `TranscriptMessage`: user/assistant message block with compact text rhythm.
- `AgentStepList`: grouped thinking, tool, approval, and result rows.
- `AgentStepRow`: collapsible state row with icon, title, metadata, and chevron.
- `StepDetailPanel`: desktop inspector and mobile expanded content.
- `ComposerBar`: input surface with attach, voice, and send controls.

## Content Sample

The prototype should show a realistic AI CLI workflow:

- User asks for a mobile/LAN CLI control interface improvement.
- Assistant clarifies the target and creates a plan.
- Tool steps create docs, inspect files, initialize a React prototype, and verify output.
- Completed steps show checks. One active or selected step shows expanded details.

## Acceptance Criteria

- The webpage demonstrates both mobile and desktop layouts in one responsive prototype.
- Step rows collapse and expand, and completed rows show a check icon.
- The visual language matches the product: calm, dense, technical, and safety-aware.
- Execution context is visible before actions: workspace, adapter, status, and boundary badges.
- The design avoids heavy cards, decorative glass, neon terminal styling, gradient text, and modal-first details.
- The page can be opened locally as a standalone HTML prototype.

## Verification Plan

- Open the prototype in a browser and verify mobile-width and desktop-width layouts.
- Toggle several step rows and confirm details remain readable.
- Check that state is not conveyed by color alone.
- Run a lightweight static inspection for broken markup or missing assets.

## Risks

- A standalone webpage can demonstrate interaction and visual direction, but it will not prove Flutter implementation details.
- The final Flutter version may need adjusted spacing and typography for native platform constraints.
