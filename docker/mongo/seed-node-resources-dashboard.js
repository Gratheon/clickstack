const dashboardName = "Node resources";
const now = new Date();

function waitForMetadata() {
  for (let attempt = 1; attempt <= 60; attempt += 1) {
    const team = db.teams.findOne({});
    const connection = db.connections.findOne({ name: "Local ClickHouse" }) || db.connections.findOne({});

    if (team && connection) {
      return { team, connection, user: db.users.findOne({}) };
    }

    print(`Waiting for HyperDX metadata (${attempt}/60)`);
    sleep(2000);
  }

  throw new Error("Timed out waiting for HyperDX team and ClickHouse connection metadata");
}

function sqlTile(id, x, y, w, h, displayType, name, sqlTemplate, connection) {
  return {
    id,
    x,
    y,
    w,
    h,
    config: {
      configType: "sql",
      displayType,
      name,
      sqlTemplate,
      connection,
    },
  };
}

const { team, connection, user } = waitForMetadata();
const connectionId = connection._id.toString();

const dashboard = {
  name: dashboardName,
  tags: ["observability", "node", "host", "docker"],
  filters: [],
  tiles: [
    sqlTile(
      "host-cpu-busy-pct",
      0,
      0,
      12,
      6,
      "line",
      "CPU busy %",
      `SELECT
  toStartOfInterval(TimeUnix, INTERVAL {intervalSeconds:Int64} second) AS ts,
  round(100 * (1 - avgIf(Value, Attributes['state'] = 'idle')), 2) AS cpu_busy_pct
FROM default.otel_metrics_gauge
WHERE MetricName = 'system.cpu.utilization'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY ts
ORDER BY ts`,
      connectionId
    ),
    sqlTile(
      "host-memory-used-pct",
      12,
      0,
      12,
      6,
      "line",
      "Memory used %",
      `SELECT
  toStartOfInterval(TimeUnix, INTERVAL {intervalSeconds:Int64} second) AS ts,
  round(100 * avgIf(Value, Attributes['state'] = 'used'), 2) AS memory_used_pct
FROM default.otel_metrics_gauge
WHERE MetricName = 'system.memory.utilization'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY ts
ORDER BY ts`,
      connectionId
    ),
    sqlTile(
      "host-load-average",
      0,
      6,
      12,
      6,
      "line",
      "Load average",
      `SELECT
  toStartOfInterval(TimeUnix, INTERVAL {intervalSeconds:Int64} second) AS ts,
  avgIf(Value, MetricName = 'system.cpu.load_average.1m') AS load_1m,
  avgIf(Value, MetricName = 'system.cpu.load_average.5m') AS load_5m,
  avgIf(Value, MetricName = 'system.cpu.load_average.15m') AS load_15m
FROM default.otel_metrics_gauge
WHERE MetricName IN ('system.cpu.load_average.1m', 'system.cpu.load_average.5m', 'system.cpu.load_average.15m')
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY ts
ORDER BY ts`,
      connectionId
    ),
    sqlTile(
      "host-filesystem-used-pct",
      12,
      6,
      12,
      6,
      "line",
      "Filesystem used %",
      `SELECT
  toStartOfInterval(TimeUnix, INTERVAL {intervalSeconds:Int64} second) AS ts,
  Attributes['mountpoint'] AS mountpoint,
  round(100 * avg(Value), 2) AS used_pct
FROM default.otel_metrics_gauge
WHERE MetricName = 'system.filesystem.utilization'
  AND Attributes['mode'] != 'ro'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY ts, mountpoint
ORDER BY ts, mountpoint`,
      connectionId
    ),
    sqlTile(
      "host-network-io",
      0,
      12,
      12,
      6,
      "line",
      "Network IO bytes",
      `SELECT
  toStartOfInterval(TimeUnix, INTERVAL {intervalSeconds:Int64} second) AS ts,
  sumIf(Value, Attributes['direction'] = 'receive') AS rx_bytes,
  sumIf(Value, Attributes['direction'] = 'transmit') AS tx_bytes
FROM default.otel_metrics_sum
WHERE MetricName = 'system.network.io'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY ts
ORDER BY ts`,
      connectionId
    ),
    sqlTile(
      "host-processes",
      12,
      12,
      12,
      6,
      "line",
      "Processes by status",
      `SELECT
  toStartOfInterval(TimeUnix, INTERVAL {intervalSeconds:Int64} second) AS ts,
  Attributes['status'] AS status,
  avg(Value) AS processes
FROM default.otel_metrics_sum
WHERE MetricName = 'system.processes.count'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY ts, status
ORDER BY ts, status`,
      connectionId
    ),
    sqlTile(
      "container-cpu-top",
      0,
      18,
      12,
      6,
      "table",
      "Container CPU %",
      `SELECT
  ResourceAttributes['container.name'] AS container,
  round(avg(Value), 2) AS cpu_pct
FROM default.otel_metrics_gauge
WHERE MetricName = 'container.cpu.utilization'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY container
ORDER BY cpu_pct DESC`,
      connectionId
    ),
    sqlTile(
      "container-memory-top",
      12,
      18,
      12,
      6,
      "table",
      "Container memory %",
      `SELECT
  ResourceAttributes['container.name'] AS container,
  round(avg(Value), 2) AS memory_pct
FROM default.otel_metrics_gauge
WHERE MetricName = 'container.memory.percent'
  AND TimeUnix >= fromUnixTimestamp64Milli({startDateMilliseconds:Int64}) AND TimeUnix < fromUnixTimestamp64Milli({endDateMilliseconds:Int64})
GROUP BY container
ORDER BY memory_pct DESC`,
      connectionId
    ),
  ],
  team: team._id,
  updatedAt: now,
  containers: [],
  savedFilterValues: [],
};

if (user) {
  dashboard.updatedBy = user._id;
}

const existing = db.dashboards.findOne({ name: dashboardName, team: team._id });

if (existing) {
  db.dashboards.updateOne(
    { _id: existing._id },
    {
      $set: dashboard,
      $setOnInsert: {
        createdAt: now,
        ...(user ? { createdBy: user._id } : {}),
      },
    },
    { upsert: true }
  );
  print(`Updated dashboard: ${dashboardName}`);
} else {
  db.dashboards.insertOne({
    ...dashboard,
    createdAt: now,
    ...(user ? { createdBy: user._id } : {}),
  });
  print(`Created dashboard: ${dashboardName}`);
}
