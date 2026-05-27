#!/bin/bash
set -euo pipefail

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="lo-kylin-builder"
OUTPUT_FILE="libreoffice-7.5.9-headless-aarch64-kylinv10.tar.gz"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  LibreOffice 7.5.9 Headless — Kylin V10 ARM64 编译  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Build dir:  ${BUILD_DIR}"
echo "Platform:   $(uname -m)"
echo "Docker:     $(docker --version)"
echo ""

docker build \
  --platform linux/arm64 \
  --progress=plain \
  -t "${IMAGE_NAME}" \
  "${BUILD_DIR}" \
  2>&1 | tee "${BUILD_DIR}/docker-build.log"

echo ""
echo ">>> Extracting artifact..."
CONTAINER_ID=$(docker create "${IMAGE_NAME}")
docker cp "${CONTAINER_ID}:/build/${OUTPUT_FILE}" "${BUILD_DIR}/${OUTPUT_FILE}"
docker rm "${CONTAINER_ID}" > /dev/null

echo ""
echo ">>> Done!"
echo "Output: ${BUILD_DIR}/${OUTPUT_FILE}"
ls -lh "${BUILD_DIR}/${OUTPUT_FILE}"
