# OpenSearch observability: WooCommerce logs → OpenSearch (homework)

OpenSearch Stack course homework — collect logs from every component of a
WooCommerce store (Nginx, MySQL, PHP, Docker container, Linux) and ship them
into an **OpenSearch** cluster with **Fluent Bit**, viewed in **OpenSearch
Dashboards**.

The store is deployed **separately** (the `woocommerce-observability` repo) and
stays running; this repo is the OpenSearch observability plane that reads its
logs.

## Architecture

```
woocommerce-observability  (EXISTING — "the store", deployed separately, :8080)
  woocommerce-nginx   ──► ./logs/nginx/*.log
  woocommerce-db      ──► ./logs/mysql/*.log          read-only host mounts
  woocommerce-wp      ──► ./logs/php/*.log            ─────────────┐
  (containers)        ──► docker container json                    │
  (host)              ──► systemd journald                          │
                                                                    ▼
                                          opensearch-observability  (THIS repo)
                                          ┌─────────────────────────────────────┐
                                          │ fluent-bit  ──►  OpenSearch 3.7.0   │
                                          │   (5 inputs)      (HTTPS, demo cert)│
                                          │                       │             │
                                          │                  OpenSearch         │
                                          │                  Dashboards 3.7.0   │
                                          │                  (Discover)         │
                                          └─────────────────────────────────────┘
```

## Components & versions (verified current)

| Component | Image | Version |
|---|---|---|
| OpenSearch | `opensearchproject/opensearch` | 3.7.0 |
| OpenSearch Dashboards | `opensearchproject/opensearch-dashboards` | 3.7.0 |
| Fluent Bit | `fluent/fluent-bit` | 5.0.9 |

OpenSearch 3.x **requires** a custom admin password (`OPENSEARCH_INITIAL_ADMIN_PASSWORD`);
the demo `admin/admin` was removed in 2.12. The password must pass zxcvbn and
**not resemble the username** `admin` (e.g. `Adm1n@…` is rejected).

## Log sources → Fluent Bit → OpenSearch (5 deliverable sources)

| Source | Fluent Bit input | Index |
|---|---|---|
| Nginx access+error | `tail` (built-in `nginx` parser / custom `nginx_error`) | `woocommerce-nginx-*` |
| MySQL/MariaDB error+slow | `tail` (custom `mariadb_error`; `Read_From_Head On` so startup logs land) | `woocommerce-mysql-*` |
| PHP-FPM | `tail` `logs/php/*.log` | `woocommerce-php-*` |
| Docker container (store containers + host k8s pods) | `tail` `/var/lib/docker/containers/*/*-json.log` (`docker` parser) | `woocommerce-container-*` |
| Linux system (systemd journald) | `systemd` input | `woocommerce-linux-*` |

Output: OpenSearch plugin, one `[OUTPUT]` per source tag → a daily index per
component. Key params: `http_user`/`http_passwd` (note: `*_passwd`, not `*_pwd`),
`suppress_type_name On` (required for OpenSearch 2.x+), `tls On` + `tls.verify Off`
(self-signed demo cert), `logstash_format On`.

## Deliverables (per the assignment)

- **Log shipper config files:** [`fluent-bit/fluent-bit.conf`](fluent-bit/fluent-bit.conf) +
  [`fluent-bit/parsers_custom.conf`](fluent-bit/parsers_custom.conf) (+ [`docker-compose.yml`](docker-compose.yml)).
- **Screenshots — logs arriving in OpenSearch** (`docs/screenshots/`):
  - `01-nginx-logs.png`
  - `02-mysql-logs.png`
  - `03-php-logs.png`
  - `04-container-logs.png`
  - `05-linux-logs.png`

## Run

Prerequisites: the WooCommerce store running in `../woocommerce-observability`
on `:8080` (its `logs/` dir is read by Fluent Bit).

```bash
cp .env.example .env            # set OPENSEARCH_ADMIN_PASSWORD + WC_LOGS_DIR
docker compose up -d opensearch
# wait for green:
curl -k -u "admin:$OPENSEARCH_ADMIN_PASSWORD" https://localhost:9202/_cluster/health
docker compose up -d            # dashboards + fluent-bit

# generate store traffic so logs flow
for i in $(seq 1 20); do curl -s -o /dev/null http://localhost:8080/; curl -s -o /dev/null http://localhost:8080/shop/; done

# verify the 5 indices landed
curl -k -u "admin:$OPENSEARCH_ADMIN_PASSWORD" "https://localhost:9202/_cat/indices/woocommerce-*?v"
```

Then **OpenSearch Dashboards** → http://localhost:5602 (login `admin` / your
password, select the **Global** tenant) → **Discover** → pick each
`woocommerce-*` index pattern to see the logs.

## Notes

- **Ports:** OpenSearch REST on `9202`, Dashboards on `5602` — chosen to avoid
  HW1's Elasticsearch (`9200`/`9201`) and Kibana (`5601`).
- **Memory lock:** `bootstrap.memory_lock` is off — Colima's runc rejects
  `RLIMIT_MEM_LOCK=-1`. OpenSearch runs fine without it (logs a warning).
- **Indices are yellow** on this single-node cluster (the replica shard can't be
  placed); data is fully available on the primary. Harmless for a demo.
- **MariaDB error log** only has startup content, so its tail input uses
  `Read_From_Head On` to ingest it; a `SELECT SLEEP(3)` populates the slow log.
- The OpenSearch node uses the security plugin's **demo self-signed cert** — fine
  for a local stack, not for anything exposed.
