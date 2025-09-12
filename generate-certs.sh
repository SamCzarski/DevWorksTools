#!/bin/bash
set -euo pipefail

CONFIG_FILE=".cert.config.yaml"

# === HELPER FUNCTIONS ===
error_exit() {
    echo "❌ Error: $1" >&2
    exit 1
}

# Prompt for a password hidden
read_password_hidden() {
    local prompt="${1:-Password: }"
    local pw1 pw2
    while true; do
        read -rsp "$prompt" pw1
        echo
        read -rsp "Confirm password: " pw2
        echo
        if [[ "$pw1" != "$pw2" ]]; then
            echo "Passwords do not match. Try again."
        elif [[ -z "$pw1" ]]; then
            echo "Password cannot be empty. Try again."
        else
            printf '%s' "$pw1"
            return 0
        fi
    done
}

# === LOAD CONFIG ===
if [[ ! -f "$CONFIG_FILE" ]]; then
    error_exit "Config file '$CONFIG_FILE' not found."
fi

# Function to read a key from YAML
get_config_value() {
    local key="$1"
    local value
    value=$(grep -E "^${key}:" "$CONFIG_FILE" | sed -E "s/^${key}:[[:space:]]*//")
    if [[ -z "$value" ]]; then
        error_exit "Missing required config key: $key"
    fi
    echo "$value"
}

CA_NAME="$(get_config_value "CA_NAME")"
SERVER_CN="$(get_config_value "SERVER_CN")"
KEYSTORE_ALIAS="$(get_config_value "KEYSTORE_ALIAS")"
DAYS_CA="$(get_config_value "DAYS_CA")"
DAYS_SERVER="$(get_config_value "DAYS_SERVER")"
OUTDIR="$(get_config_value "OUTDIR")"

# Prompt for PKCS#12 password
P12_PASSWORD="$(read_password_hidden "Enter PKCS#12 password: ")"

mkdir -p "$OUTDIR"

# === BEGIN CERT GENERATION ===
echo "[1/8] Generating Root CA key and cert..."
openssl genrsa -out "$OUTDIR/rootCA.key" 4096
openssl req -x509 -new -nodes -key "$OUTDIR/rootCA.key" -sha256 -days "$DAYS_CA" \
  -out "$OUTDIR/rootCA.crt" \
  -subj "/C=CA/ST=Ontario/L=Ottawa/O=Czarski DevWorks/CN=${CA_NAME}" \
  -addext basicConstraints=critical,CA:TRUE \
  -addext keyUsage=critical,keyCertSign,cRLSign

echo "[2/8] Generating server key..."
openssl genrsa -out "$OUTDIR/server.key" 2048

echo "[3/8] Creating server CSR..."
openssl req -new -key "$OUTDIR/server.key" \
  -out "$OUTDIR/server.csr" \
  -subj "/C=CA/ST=Ontario/L=Ottawa/O=Dev Server/CN=${SERVER_CN}"

echo "[4/8] Creating server certificate extensions..."
cat > "$OUTDIR/server.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVER_CN}
DNS.2 = hydra
DNS.3 = host.docker.internal
EOF

echo "[5/8] Signing server cert with CA..."
openssl x509 -req -in "$OUTDIR/server.csr" \
  -CA "$OUTDIR/rootCA.crt" -CAkey "$OUTDIR/rootCA.key" -CAcreateserial \
  -out "$OUTDIR/server.crt" -days "$DAYS_SERVER" -sha256 \
  -extfile "$OUTDIR/server.ext"

echo "[6/8] Creating PKCS#12 keystore for Spring Boot..."
openssl pkcs12 -export \
  -in "$OUTDIR/server.crt" \
  -inkey "$OUTDIR/server.key" \
  -out "$OUTDIR/keystore.p12" \
  -name "$KEYSTORE_ALIAS" \
  -CAfile "$OUTDIR/rootCA.crt" \
  -caname root \
  -passout pass:"$P12_PASSWORD"

echo "[7/8] Creating full chain for Hydra..."
cat "$OUTDIR/server.crt" "$OUTDIR/rootCA.crt" > "$OUTDIR/server-fullchain.crt"

echo "[8/8] Creating server pem..."
cat "$OUTDIR/server-fullchain.crt" "$OUTDIR/server.key" > "$OUTDIR/server.pem"

echo "✅ Done!"
echo "------------------------------------------------"
echo "CA cert (import into Authorities, public): $OUTDIR/rootCA.crt"
echo "Spring Boot keystore:                      $OUTDIR/keystore.p12"
echo "Keystore alias:                             $KEYSTORE_ALIAS"
echo "Hydra cert:                                 $OUTDIR/server-fullchain.crt"
echo "Hydra key:                                  $OUTDIR/server.key"
echo "Server pem:                                  $OUTDIR/server.pem"
echo "------------------------------------------------"
