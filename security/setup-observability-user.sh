#!/bin/sh
# Create the least-privilege `observability` user + `observability_writer` role
# in the OpenSearch cluster, so the write-path integrations (Fluent Bit,
# os-health collector, Data Prepper) don't have to use `admin`.
#
# Run once as admin:
#   ADMIN_PW=... OBS_PW=... sh security/setup-observability-user.sh
set -e
OS="${OS_URL:-https://localhost:9202}"
A="admin:${ADMIN_PW:?set ADMIN_PW (admin password)}"
P="${OBS_PW:?set OBS_PW (new observability user password)}"

echo "creating role observability_writer..."
curl -fsk -u "$A" -X PUT "$OS/_plugins/_security/api/roles/observability_writer" \
  -H 'Content-Type: application/json' \
  --data-binary @security/role-observability-writer.json >/dev/null

echo "creating internal user observability..."
curl -fsk -u "$A" -X PUT "$OS/_plugins/_security/api/internalusers/observability" \
  -H 'Content-Type: application/json' \
  -d "{\"password\":\"$P\",\"backend_roles\":[]}" >/dev/null

echo "mapping role -> user..."
curl -fsk -u "$A" -X PUT "$OS/_plugins/_security/api/rolesmapping/observability_writer" \
  -H 'Content-Type: application/json' \
  -d '{"users":["observability"]}' >/dev/null

echo "done. user 'observability' can write woocommerce-*/os-health-*/otel-v1-apm-* only."
