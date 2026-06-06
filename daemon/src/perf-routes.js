'use strict';

const CLOCK_SYNC_QUALITIES = new Set(['good', 'degraded', 'poor', 'unknown']);

async function handlePerfRoute({ method, url, device, readJson, json, perfConfig, perfStore }) {
  if (!url.pathname.startsWith('/api/perf/')) return false;
  const config = perfConfig || { enabled: false };

  if (method === 'GET' && url.pathname === '/api/perf/config') {
    if (!config.enabled) {
      json(200, { enabled: false });
      return true;
    }
    const run = perfStore?.ensureRun ? perfStore.ensureRun() : config.ensureRun();
    json(200, {
      enabled: true,
      runId: run.id,
      sampleRate: config.sampleRate,
      maxQueueSize: config.maxQueueSize,
      maxBatchSize: config.maxBatchSize
    });
    return true;
  }

  if (method === 'POST' && url.pathname === '/api/perf/time-sync') {
    const daemonReceiveWallMs = Date.now();
    const body = await readJson();
    assertObject(body, 'body');
    assertString(body.runId, 'runId');
    assertString(body.appSessionId, 'appSessionId');
    assertInteger(body.mobileSendWallMs, 'mobileSendWallMs');
    assertInteger(body.mobileSendMonoUs, 'mobileSendMonoUs');
    json(200, {
      daemonReceiveWallMs,
      daemonSendWallMs: Date.now()
    });
    return true;
  }

  if (method === 'POST' && url.pathname === '/api/perf/mobile-marks') {
    if (!config.enabled) {
      json(200, { accepted: 0, dropped: 0, disabled: true });
      return true;
    }
    const daemonReceiveWallMs = Date.now();
    const activeRun = perfStore?.ensureRun ? perfStore.ensureRun() : config.ensureRun();
    const batch = validateMobileBatch(await readJson(), config, daemonReceiveWallMs, activeRun?.id, device?.id);
    batch.daemonSendWallMs = Date.now();
    try {
      perfStore.writeMobileBatch(batch);
    } catch {
      // Defensive only; the store is expected to swallow diagnostic write failures.
    }
    json(200, {
      accepted: batch.marks.length,
      dropped: batch.droppedCountSinceLastSuccessfulFlush,
      daemonReceiveWallMs: batch.daemonReceiveWallMs,
      daemonSendWallMs: batch.daemonSendWallMs
    });
    return true;
  }

  throw perfHttpError(404, 'PERF_ROUTE_NOT_FOUND', 'perf route not found');
}

function validateMobileBatch(body, config, daemonReceiveWallMs, activeRunId, authenticatedDeviceId) {
  assertObject(body, 'body');
  assertString(body.runId, 'runId');
  if (activeRunId && body.runId !== activeRunId) throw badRequest('runId must match the active perf run');
  assertString(body.deviceId, 'deviceId');
  if (authenticatedDeviceId && body.deviceId !== authenticatedDeviceId) {
    throw badRequest('deviceId must match the authenticated device');
  }
  assertString(body.appSessionId, 'appSessionId');
  assertInteger(body.mobileSentWallMs, 'mobileSentWallMs');
  assertInteger(body.mobileSentMonoUs, 'mobileSentMonoUs');
  const droppedCountSinceLastSuccessfulFlush = assertNonNegativeInteger(
    body.droppedCountSinceLastSuccessfulFlush,
    'droppedCountSinceLastSuccessfulFlush'
  );
  const droppedCriticalCountSinceLastSuccessfulFlush = assertNonNegativeInteger(
    body.droppedCriticalCountSinceLastSuccessfulFlush,
    'droppedCriticalCountSinceLastSuccessfulFlush'
  );
  const droppedNonCriticalCountSinceLastSuccessfulFlush = assertNonNegativeInteger(
    body.droppedNonCriticalCountSinceLastSuccessfulFlush,
    'droppedNonCriticalCountSinceLastSuccessfulFlush'
  );
  const clockSync = validateClockSync(body.clockSync);
  if (!Array.isArray(body.marks)) throw badRequest('marks must be an array');
  if (body.marks.length > config.maxBatchSize) {
    throw perfHttpError(413, 'PERF_BATCH_TOO_LARGE', `marks must contain at most ${config.maxBatchSize} items`);
  }
  const marks = body.marks.map((mark, index) => validateMark(mark, index, config));
  return {
    runId: body.runId,
    deviceId: body.deviceId,
    appSessionId: body.appSessionId,
    mobileSentWallMs: body.mobileSentWallMs,
    mobileSentMonoUs: body.mobileSentMonoUs,
    droppedCountSinceLastSuccessfulFlush,
    droppedCriticalCountSinceLastSuccessfulFlush,
    droppedNonCriticalCountSinceLastSuccessfulFlush,
    clockSync,
    marks,
    daemonReceiveWallMs
  };
}

function validateClockSync(value) {
  assertObject(value, 'clockSync');
  assertNumber(value.offsetEstimateMs, 'clockSync.offsetEstimateMs');
  assertNumber(value.roundTripMs, 'clockSync.roundTripMs');
  assertInteger(value.ageMs, 'clockSync.ageMs');
  if (!CLOCK_SYNC_QUALITIES.has(value.quality)) throw badRequest('clockSync.quality is invalid');
  if (typeof value.clockDriftWarning !== 'boolean') throw badRequest('clockSync.clockDriftWarning must be a boolean');
  return {
    offsetEstimateMs: value.offsetEstimateMs,
    roundTripMs: value.roundTripMs,
    ageMs: value.ageMs,
    quality: value.quality,
    clockDriftWarning: value.clockDriftWarning
  };
}

function validateMark(value, index, config) {
  assertObject(value, `marks[${index}]`);
  assertString(value.name, `marks[${index}].name`);
  if (value.source !== 'mobile') throw badRequest(`marks[${index}].source must be mobile`);
  assertInteger(value.wallTimeMs, `marks[${index}].wallTimeMs`);
  assertInteger(value.monotonicUs, `marks[${index}].monotonicUs`);
  if (value.critical !== undefined && typeof value.critical !== 'boolean') throw badRequest(`marks[${index}].critical must be a boolean`);
  if (value.clockDriftWarning !== undefined && typeof value.clockDriftWarning !== 'boolean') throw badRequest(`marks[${index}].clockDriftWarning must be a boolean`);
  const metadata = value.metadata === undefined ? {} : value.metadata;
  assertObject(metadata, `marks[${index}].metadata`);
  validateMetadata(metadata, `marks[${index}].metadata`);
  const metadataJson = JSON.stringify(metadata);
  if (Buffer.byteLength(metadataJson, 'utf8') > config.maxMetadataBytes) {
    throw badRequest(`marks[${index}].metadata is too large`);
  }
  return {
    name: value.name,
    source: value.source,
    wallTimeMs: value.wallTimeMs,
    monotonicUs: value.monotonicUs,
    conversationId: optionalString(value.conversationId, `marks[${index}].conversationId`),
    seq: optionalInteger(value.seq, `marks[${index}].seq`),
    eventType: optionalString(value.eventType, `marks[${index}].eventType`),
    correlationId: optionalString(value.correlationId, `marks[${index}].correlationId`),
    critical: value.critical === true,
    clockDriftWarning: value.clockDriftWarning === true,
    metadata
  };
}

function validateMetadata(metadata, field) {
  for (const [key, value] of Object.entries(metadata)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(key)) throw badRequest(`${field} has an invalid key`);
    if (
      value !== null &&
      typeof value !== 'string' &&
      typeof value !== 'number' &&
      typeof value !== 'boolean'
    ) {
      throw badRequest(`${field}.${key} must be a primitive JSON value`);
    }
    if (typeof value === 'number' && !Number.isFinite(value)) {
      throw badRequest(`${field}.${key} must be a finite number`);
    }
  }
}

function assertObject(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw badRequest(`${field} must be an object`);
  }
}

function assertString(value, field) {
  if (typeof value !== 'string' || value.length === 0) throw badRequest(`${field} must be a non-empty string`);
}

function optionalString(value, field) {
  if (value === undefined || value === null) return null;
  assertString(value, field);
  return value;
}

function assertInteger(value, field) {
  if (!Number.isSafeInteger(value)) throw badRequest(`${field} must be an integer`);
}

function optionalInteger(value, field) {
  if (value === undefined || value === null) return null;
  assertInteger(value, field);
  return value;
}

function assertNonNegativeInteger(value, field) {
  assertInteger(value, field);
  if (value < 0) throw badRequest(`${field} must be non-negative`);
  return value;
}

function assertNumber(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw badRequest(`${field} must be a finite number`);
}

function badRequest(message) {
  return perfHttpError(400, 'PERF_BAD_REQUEST', message);
}

function perfHttpError(status, code, message) {
  const error = new Error(message);
  error.status = status;
  error.code = code;
  return error;
}

module.exports = { handlePerfRoute };
