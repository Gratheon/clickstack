#!/bin/sh
set -eu

host="${CLICKHOUSE_HOST:-clickhouse}"
database="${HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE:-default}"
log_days="${CLICKSTACK_LOG_RETENTION_DAYS:-14}"
trace_days="${CLICKSTACK_TRACE_RETENTION_DAYS:-7}"
metric_days="${CLICKSTACK_METRIC_RETENTION_DAYS:-30}"
session_days="${CLICKSTACK_SESSION_RETENTION_DAYS:-14}"

until clickhouse-client --host "$host" --query "SELECT 1" >/dev/null 2>&1; do
  sleep 2
done

while true; do
  apply_ttl() {
    table="$1"
    expression="$2"

    exists="$(clickhouse-client --host "$host" --query \
      "SELECT count() FROM system.tables WHERE database = '${database}' AND name = '${table}'")"

    if [ "$exists" = "1" ]; then
      clickhouse-client --host "$host" --query "ALTER TABLE ${database}.${table} MODIFY TTL ${expression}"
    fi
  }

  apply_ttl otel_logs "TimestampTime + INTERVAL ${log_days} DAY"
  apply_ttl otel_traces "Timestamp + INTERVAL ${trace_days} DAY"
  apply_ttl otel_metrics_gauge "TimeUnix + INTERVAL ${metric_days} DAY"
  apply_ttl otel_metrics_sum "TimeUnix + INTERVAL ${metric_days} DAY"
  apply_ttl otel_metrics_histogram "TimeUnix + INTERVAL ${metric_days} DAY"
  apply_ttl hyperdx_sessions "TimestampTime + INTERVAL ${session_days} DAY"

  sleep 3600
done

