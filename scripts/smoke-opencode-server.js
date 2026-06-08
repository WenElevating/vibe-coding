'use strict';

function parseOpenCodeSseFrames(text) {
  const frames = [];
  let dataLines = [];
  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.trimEnd();
    if (line === '') {
      pushFrame(frames, dataLines);
      dataLines = [];
      continue;
    }
    if (line.startsWith('data:')) dataLines.push(line.slice(5).trimStart());
  }
  pushFrame(frames, dataLines);
  return frames;
}

function pushFrame(frames, dataLines) {
  if (!dataLines.length) return;
  const text = dataLines.join('\n').trim();
  if (!text) return;
  try {
    frames.push(JSON.parse(text));
  } catch (error) {
    frames.push({ type: 'parse.error', message: error.message, raw: text.slice(0, 4096) });
  }
}

module.exports = {
  parseOpenCodeSseFrames
};

if (require.main === module) {
  console.log('OpenCode smoke helper loaded. Live route probes are still not_run unless manifest gates record pass.');
}
