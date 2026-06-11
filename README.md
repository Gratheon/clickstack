# Gratheon ClickStack

ClickStack for Gratheon observability: OpenTelemetry Collector receives logs/traces/metrics, ClickHouse stores them, HyperDX provides the UI, and MongoDB stores HyperDX metadata.

## Development

```sh
cd /Users/artjom/git/gratheon/clickstack
cp .env.example .env
just start
```

Local URLs:

- HyperDX UI: http://localhost:8081
- HyperDX API: http://localhost:8000
- OTLP HTTP: `http://localhost:4318`
- OTLP gRPC: `http://localhost:4317`
- Collector health: http://localhost:13133
- Collector metrics: http://localhost:8888/metrics
- ClickHouse HTTP: http://localhost:8123
- ClickHouse native: `localhost:9001`
- Node resources dashboard: http://localhost:8081/dashboards/list

Point local services at ClickStack:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=<service-name>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=dev,service.namespace=gratheon
HYPERDX_API_KEY=local-gratheon-clickstack
```

For services running in Docker but outside this compose project, `host.docker.internal:4318` is often the easiest local endpoint.
After first registering in HyperDX, run `just set-dev-ingest-key` once to set the local team collector key to `local-gratheon-clickstack`.

## Production

```sh
cd /Users/artjom/git/gratheon/clickstack
just start-prod
```

Production compose uses named Docker volumes and keeps ClickHouse/Mongo internal. HyperDX binds to `127.0.0.1:8080` and `127.0.0.1:8000`, so put routing in front with nginx/Caddy/Traefik.

Production also collects node and Docker metrics from the host via the OpenTelemetry Collector. The collector mounts `/` at `/hostfs` for hostmetrics and `/var/run/docker.sock` for Docker container metrics, then `dashboard-seed` creates or updates the `Node resources` dashboard in HyperDX metadata.

Production retention is intentionally small: app telemetry is kept for 7 days, ClickHouse internal diagnostic logs are kept for 1 day, and the retention worker enforces a 1 GiB ClickHouse data cap by pruning diagnostic logs and then oldest telemetry partitions if needed.

The nginx site config is in `config/nginx.conf`:

```sh
sudo ln -s /www/clickstack/config/nginx.conf /etc/nginx/sites-enabled/clickstack.conf
sudo nginx -t
sudo systemctl reload nginx
```

Production service env:

```sh
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_SERVICE_NAME=<service-name>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=prod,service.namespace=gratheon
HYPERDX_API_KEY=<secret>
```

## Notes

- Do not expose MongoDB.
- Do not expose ClickHouse publicly.
- Treat `HYPERDX_API_KEY` as the ingest secret.
- Dev and production collect host and Docker metrics via `/` and `/var/run/docker.sock`.
