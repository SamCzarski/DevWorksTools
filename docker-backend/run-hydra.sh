#!/bin/sh
set -e

# Read secrets from Docker secrets files
export DSN=$(cat /run/secrets/hydra_db_dsn)
export SECRETS_SYSTEM=$(cat /run/secrets/hydra_secret_system)
export OIDC_SUBJECT_SALT=$(cat /run/secrets/hydra_oidc_salt)
export REDIS_URL=$(cat /run/secrets/redis_url)

# Run Hydra with environment variables
exec hydra serve all --config /etc/hydra/hydra.yml
