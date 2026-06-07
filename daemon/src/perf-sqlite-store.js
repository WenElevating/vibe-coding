'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

class PerfSqliteStore {
  constructor({ dbPath = defaultPerfDbPath(), config, now = () => new Date() } = {}) {
    this.dbPath = dbPath;
    this.config = config || { enabled: false, ensureRun: () => null };
    this.now = now;
    this.db = null;
  }

  ensureRun() {
    if (!this.config.enabled) return null;
    const run = this.config.ensureRun();
    if (!run) return null;
    const db = this.ensureDb();
    db.prepare(`
      INSERT OR IGNORE INTO perf_runs(id, started_at, metadata_json)
      VALUES (?, ?, '{}')
    `).run(run.id, run.startedAt);
    return run;
  }

  writeDaemonMark(mark) {
    if (!this.config.enabled) return;
    try {
      const run = this.ensureRun();
      if (!run) return;
      this.insertMark({
        ...mark,
        runId: mark.runId || run.id,
        mobileBatchId: null,
        daemonReceiveWallMs: mark.daemonReceiveWallMs ?? null
      });
    } catch {
      // Perf writes are diagnostic only and must not affect business APIs.
    }
  }

  writeMobileBatch(batch) {
    if (!this.config.enabled) return null;
    try {
      this.ensureRun();
      const db = this.ensureDb();
      const now = this.now().toISOString();
      const receiveWallMs = batch.daemonReceiveWallMs;
      const sendWallMs = batch.daemonSendWallMs;
      db.exec('BEGIN');
      try {
        const result = db.prepare(`
          INSERT INTO perf_mobile_batches(
            run_id,
            device_id,
            app_session_id,
            mobile_sent_wall_ms,
            mobile_sent_mono_us,
            daemon_receive_wall_ms,
            daemon_send_wall_ms,
            clock_offset_estimate_ms,
            clock_round_trip_ms,
            clock_sync_age_ms,
            clock_sync_quality,
            clock_drift_warning,
            dropped_count_since_last_successful_flush,
            dropped_critical_count_since_last_successful_flush,
            dropped_non_critical_count_since_last_successful_flush,
            created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `).run(
          batch.runId,
          batch.deviceId,
          batch.appSessionId,
          batch.mobileSentWallMs,
          batch.mobileSentMonoUs,
          receiveWallMs,
          sendWallMs,
          batch.clockSync.offsetEstimateMs,
          batch.clockSync.roundTripMs,
          batch.clockSync.ageMs,
          batch.clockSync.quality,
          batch.clockSync.clockDriftWarning ? 1 : 0,
          batch.droppedCountSinceLastSuccessfulFlush,
          batch.droppedCriticalCountSinceLastSuccessfulFlush,
          batch.droppedNonCriticalCountSinceLastSuccessfulFlush,
          now
        );
        const mobileBatchId = Number(result.lastInsertRowid);
        for (const mark of batch.marks) {
          this.insertMark({
            ...mark,
            runId: batch.runId,
            mobileBatchId,
            daemonReceiveWallMs: receiveWallMs,
            createdAt: now
          });
        }
        db.exec('COMMIT');
        return mobileBatchId;
      } catch (error) {
        try { db.exec('ROLLBACK'); } catch {}
        throw error;
      }
    } catch {
      return null;
    }
  }

  close() {
    if (!this.db) return;
    this.db.close();
    this.db = null;
  }

  ensureDb() {
    if (this.db) return this.db;
    fs.mkdirSync(path.dirname(this.dbPath), { recursive: true });
    this.db = new DatabaseSync(this.dbPath);
    this.db.exec('PRAGMA foreign_keys = ON');
    this.migrate();
    return this.db;
  }

  migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS perf_runs (
        id TEXT PRIMARY KEY,
        scenario TEXT,
        adapter TEXT,
        device_id TEXT,
        conversation_id TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}'
      );

      CREATE TABLE IF NOT EXISTS perf_mobile_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT,
        device_id TEXT,
        app_session_id TEXT,
        mobile_sent_wall_ms INTEGER,
        mobile_sent_mono_us INTEGER,
        daemon_receive_wall_ms INTEGER,
        daemon_send_wall_ms INTEGER,
        clock_offset_estimate_ms REAL,
        clock_round_trip_ms REAL,
        clock_sync_age_ms INTEGER,
        clock_sync_quality TEXT,
        clock_drift_warning INTEGER NOT NULL DEFAULT 0,
        dropped_count_since_last_successful_flush INTEGER NOT NULL DEFAULT 0,
        dropped_critical_count_since_last_successful_flush INTEGER NOT NULL DEFAULT 0,
        dropped_non_critical_count_since_last_successful_flush INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS perf_marks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT,
        mobile_batch_id INTEGER,
        source TEXT NOT NULL,
        name TEXT NOT NULL,
        wall_time_ms INTEGER,
        monotonic_us INTEGER,
        critical INTEGER NOT NULL DEFAULT 0,
        clock_drift_warning INTEGER NOT NULL DEFAULT 0,
        daemon_receive_wall_ms INTEGER,
        conversation_id TEXT,
        seq INTEGER,
        event_type TEXT,
        correlation_id TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        FOREIGN KEY(mobile_batch_id) REFERENCES perf_mobile_batches(id)
      );

      CREATE INDEX IF NOT EXISTS idx_perf_marks_run_name
        ON perf_marks(run_id, name);

      CREATE INDEX IF NOT EXISTS idx_perf_marks_correlation
        ON perf_marks(correlation_id, source, name);

      CREATE INDEX IF NOT EXISTS idx_perf_mobile_batches_run
        ON perf_mobile_batches(run_id, app_session_id, created_at);
    `);
  }

  insertMark(mark) {
    const db = this.ensureDb();
    db.prepare(`
      INSERT INTO perf_marks(
        run_id,
        mobile_batch_id,
        source,
        name,
        wall_time_ms,
        monotonic_us,
        critical,
        clock_drift_warning,
        daemon_receive_wall_ms,
        conversation_id,
        seq,
        event_type,
        correlation_id,
        metadata_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      mark.runId ?? null,
      mark.mobileBatchId ?? null,
      mark.source,
      mark.name,
      mark.wallTimeMs ?? null,
      mark.monotonicUs ?? null,
      mark.critical ? 1 : 0,
      mark.clockDriftWarning ? 1 : 0,
      mark.daemonReceiveWallMs ?? null,
      mark.conversationId ?? null,
      mark.seq ?? null,
      mark.eventType ?? null,
      mark.correlationId ?? null,
      JSON.stringify(mark.metadata || {}),
      mark.createdAt || this.now().toISOString()
    );
  }
}

function defaultPerfDbPath() {
  return path.resolve(process.cwd(), 'data', 'app', 'perf.sqlite');
}

module.exports = { PerfSqliteStore, defaultPerfDbPath };
