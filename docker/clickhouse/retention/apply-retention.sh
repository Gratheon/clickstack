#!/bin/sh
set -eu

host="${CLICKHOUSE_HOST:-clickhouse}"
database="${HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE:-default}"
log_days="${CLICKSTACK_LOG_RETENTION_DAYS:-14}"
trace_days="${CLICKSTACK_TRACE_RETENTION_DAYS:-7}"
metric_days="${CLICKSTACK_METRIC_RETENTION_DAYS:-30}"
session_days="${CLICKSTACK_SESSION_RETENTION_DAYS:-14}"
system_log_days="${CLICKSTACK_SYSTEM_LOG_RETENTION_DAYS:-7}"
max_bytes="${CLICKSTACK_MAX_BYTES:-0}"
system_log_tables="'trace_log','part_log','metric_log','asynchronous_metric_log','query_log','processors_profile_log','query_thread_log','query_views_log','text_log','opentelemetry_span_log','crash_log'"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

query() {
  clickhouse-client --host "$host" --query "$1"
}

until query "SELECT 1" >/dev/null 2>&1; do
  sleep 2
done

table_exists() {
  table_database="$1"
  table_name="$2"

  query "SELECT count() FROM system.tables WHERE database = '${table_database}' AND name = '${table_name}'"
}

apply_ttl() {
  table_database="$1"
  table_name="$2"
  expression="$3"

  exists="$(table_exists "$table_database" "$table_name")"

  if [ "$exists" = "1" ]; then
    if ! query "ALTER TABLE ${table_database}.${table_name} MODIFY TTL ${expression}"; then
      log "Failed to apply TTL to ${table_database}.${table_name}"
    fi
  fi
}

retained_bytes() {
  query "
    SELECT toUInt64(coalesce(sum(bytes_on_disk), 0))
    FROM system.parts
    WHERE active
      AND (
        database = '${database}'
        OR (database = 'system' AND table IN (${system_log_tables}))
      )"
}

truncate_system_log_tables() {
  for table in trace_log part_log metric_log asynchronous_metric_log query_log processors_profile_log query_thread_log query_views_log text_log opentelemetry_span_log crash_log; do
    exists="$(table_exists system "$table")"

    if [ "$exists" = "1" ]; then
      log "Truncating system.${table} to enforce ClickStack size cap"
      if ! query "TRUNCATE TABLE system.${table}"; then
        log "Failed to truncate system.${table}"
      fi
    fi
  done
}

drop_oldest_database_partition() {
  row="$(query "
    SELECT table, partition_id
    FROM
    (
      SELECT
        table,
        partition_id,
        sum(bytes_on_disk) AS bytes
      FROM system.parts
      WHERE active
        AND database = '${database}'
        AND partition_id != ''
      GROUP BY table, partition_id
      ORDER BY partition_id ASC, bytes DESC
      LIMIT 1
    )
    FORMAT TabSeparatedRaw")"

  if [ -z "$row" ]; then
    return 1
  fi

  table="$(printf '%s' "$row" | cut -f1)"
  partition_id="$(printf '%s' "$row" | cut -f2)"

  if [ -z "$table" ] || [ -z "$partition_id" ]; then
    return 1
  fi

  log "Dropping ${database}.${table} partition ${partition_id} to enforce ClickStack size cap"
  if ! query "ALTER TABLE ${database}.${table} DROP PARTITION ID '${partition_id}'"; then
    log "Failed to drop ${database}.${table} partition ${partition_id}"
    return 1
  fi
}

enforce_size_cap() {
  if [ "$max_bytes" -le 0 ] 2>/dev/null; then
    return
  fi

  total="$(retained_bytes)"

  if [ "$total" -le "$max_bytes" ]; then
    return
  fi

  log "ClickStack retained ClickHouse data is ${total} bytes; cap is ${max_bytes} bytes"
  truncate_system_log_tables
  total="$(retained_bytes)"

  attempts=0
  while [ "$total" -gt "$max_bytes" ] && [ "$attempts" -lt 100 ]; do
    if ! drop_oldest_database_partition; then
      break
    fi

    total="$(retained_bytes)"
    attempts=$((attempts + 1))
  done

  if [ "$total" -gt "$max_bytes" ]; then
    log "ClickStack retained ClickHouse data is still ${total} bytes after cap enforcement"
  else
    log "ClickStack retained ClickHouse data is now ${total} bytes"
  fi
}

while true; do
  apply_ttl "${database}" otel_logs "TimestampTime + INTERVAL ${log_days} DAY"
  apply_ttl "${database}" otel_traces "Timestamp + INTERVAL ${trace_days} DAY"
  apply_ttl "${database}" otel_traces_trace_id_ts "toDateTime(Start) + INTERVAL ${trace_days} DAY"
  apply_ttl "${database}" otel_metrics_gauge "TimeUnix + INTERVAL ${metric_days} DAY"
  apply_ttl "${database}" otel_metrics_sum "TimeUnix + INTERVAL ${metric_days} DAY"
  apply_ttl "${database}" otel_metrics_histogram "TimeUnix + INTERVAL ${metric_days} DAY"
  apply_ttl "${database}" otel_metrics_exponential_histogram "toDateTime(TimeUnix) + INTERVAL ${metric_days} DAY"
  apply_ttl "${database}" otel_metrics_summary "toDateTime(TimeUnix) + INTERVAL ${metric_days} DAY"
  apply_ttl "${database}" hyperdx_sessions "TimestampTime + INTERVAL ${session_days} DAY"

  apply_ttl system trace_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system part_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system metric_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system asynchronous_metric_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system query_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system processors_profile_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system query_thread_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system query_views_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system text_log "event_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system opentelemetry_span_log "finish_date + INTERVAL ${system_log_days} DAY"
  apply_ttl system crash_log "event_date + INTERVAL ${system_log_days} DAY"

  enforce_size_cap

  sleep 3600
done
