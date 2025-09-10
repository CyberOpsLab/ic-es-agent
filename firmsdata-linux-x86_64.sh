#!/usr/bin/env bash
set -euo pipefail

FLEET_URL="${1:?Usage: $0 <fleet_url> <enrollment_token>}"
ENROLL_TOKEN="${2:?Usage: $0 <fleet_url> <enrollment_token>}"

VER="9.1.3"
PKG="elastic-agent-${VER}-linux-x86_64"
TARBALL="${PKG}.tar.gz"
BASE_DIR="${HOME}/${PKG}"
CA_URL="https://raw.githubusercontent.com/CyberOpsLab/ic-es-agent/refs/heads/main/fd-ca.crt"
CA_PATH="${BASE_DIR}/ca.crt"

cd "${HOME}"

# Clean old artifacts
rm -rf "${BASE_DIR}" "${TARBALL}" || true

# Download and extract
curl -fsSL -o "${TARBALL}" "https://artifacts.elastic.co/downloads/beats/elastic-agent/${TARBALL}"
tar xzf "${TARBALL}"
rm -f "${TARBALL}"

# Drop CA into the agent dir
curl -fsSL -o "${CA_PATH}" "${CA_URL}"

cd "${BASE_DIR}"

# Install with certificate authorities
sudo ./elastic-agent install \
  --url="${FLEET_URL}" \
  --enrollment-token="${ENROLL_TOKEN}" \
  --certificate-authorities="$(pwd)/ca.crt"
