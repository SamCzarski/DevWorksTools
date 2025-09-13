#!/bin/bash
set -e

# Directory to store generated secret files
SECRETS_DIR="secrets"
mkdir -p "$SECRETS_DIR"

# Decode the encrypted YAML file
DECRYPTED=$(sops -d enc.secrets.yaml)

# Extract each value
HYDRA_DB_DSN=$(echo "$DECRYPTED" | yq -r '.HYDRA_DB_DSN')
HYDRA_DB_PASSWORD=$(echo "$DECRYPTED" | yq -r '.HYDRA_DB_PASSWORD')
HYDRA_OIDC_SALT=$(echo "$DECRYPTED" | yq -r '.HYDRA_OIDC_SALT')
HYDRA_SECRET_SYSTEM=$(echo "$DECRYPTED" | yq -r '.HYDRA_SECRET_SYSTEM')
REDIS_PASSWORD=$(echo "$DECRYPTED" | yq -r '.REDIS_PASSWORD')

# Write files
echo "$HYDRA_DB_DSN" > "$SECRETS_DIR/hydra_db_dsn.txt"
echo "$HYDRA_DB_PASSWORD" > "$SECRETS_DIR/hydra_db_password.txt"
echo "$HYDRA_OIDC_SALT" > "$SECRETS_DIR/hydra_oidc_salt.txt"
echo "$HYDRA_SECRET_SYSTEM" > "$SECRETS_DIR/hydra_secret_system.txt"
echo "requirepass $REDIS_PASSWORD" > "$SECRETS_DIR/redis.conf"
echo "redis://:$REDIS_PASSWORD@redis:6379/0" > "$SECRETS_DIR/redis_url.txt"

echo "Secrets extracted to $SECRETS_DIR"

