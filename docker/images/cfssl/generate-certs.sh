#!/bin/bash
set -eu

CA_INPUT="${CA_INPUT:-/ca-input}"
CERTS_DIR="${CERTS_DIR:-/certs}"

echo "[$(date)] generate-certs: starting certificate generation..."

# Verify CA input exists
if [[ ! -f "${CA_INPUT}/ca.pem" ]] || [[ ! -f "${CA_INPUT}/ca-key.pem" ]]; then
  echo >&2 "ERROR: CA cert (${CA_INPUT}/ca.pem) or key (${CA_INPUT}/ca-key.pem) not found"
  exit 1
fi

# Create working directory
WORK_DIR=$(mktemp -d)
cd "${WORK_DIR}"

# Write CA signing config
cat > ca-config.json <<'EOF'
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "etcd": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

# Function to generate a certificate
gencert() {
  local cn=$1
  local alts=$2
  local dest=$3

  cat > cert-request.json <<CERTEOF
{
  "CN": "${cn}",
  "key": {
    "algo": "rsa",
    "size": 2048
  }
}
CERTEOF

  echo "[$(date)] generating certificate for ${cn} (SANs: ${alts})..."
  cfssl gencert \
    -ca="${CA_INPUT}/ca.pem" \
    -ca-key="${CA_INPUT}/ca-key.pem" \
    -config=ca-config.json \
    -hostname="${alts}" \
    -profile=etcd \
    cert-request.json | cfssljson -bare out

  mkdir -p "${CERTS_DIR}/${dest}"
  mv out.pem     "${CERTS_DIR}/${dest}/cert.pem"
  mv out-key.pem "${CERTS_DIR}/${dest}/key.pem"
  chmod 644 "${CERTS_DIR}/${dest}/cert.pem"
  chmod 644 "${CERTS_DIR}/${dest}/key.pem"

  echo "[$(date)] >> ${CERTS_DIR}/${dest}/cert.pem"
  openssl x509 -noout -subject -issuer -in "${CERTS_DIR}/${dest}/cert.pem"
}

# Generate etcd-tls server certificate
# SANs include: localhost, etcd-tls hostname (Docker DNS), agent hostname, core hostname
gencert "etcd-tls" \
        "127.0.0.1,localhost,etcd-tls,agent,core" \
        "etcd-tls"

# Generate consul server certificate
gencert "consul" \
        "127.0.0.1,localhost,consul,server.phalanx.consul" \
        "consul"

# Copy CA cert to shared volume for consumers
cp "${CA_INPUT}/ca.pem" "${CERTS_DIR}/ca.pem"
chmod 644 "${CERTS_DIR}/ca.pem"

# Cleanup
rm -rf "${WORK_DIR}"

echo "[$(date)] generate-certs: complete."
