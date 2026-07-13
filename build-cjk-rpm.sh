#!/bin/sh
set -eu

output_dir=${1:-dist}
packager_image=libreoffice-cjk-packager:latest
build_network=${DOCKER_BUILD_NETWORK:-default}

case "$output_dir" in
  ''|/) echo "refusing unsafe output directory: $output_dir" >&2; exit 2 ;;
esac

docker build \
  --network "$build_network" \
  --build-arg HTTP_PROXY="${HTTP_PROXY:-}" \
  --build-arg HTTPS_PROXY="${HTTPS_PROXY:-}" \
  --build-arg NO_PROXY="${NO_PROXY:-}" \
  --target packager \
  -t "$packager_image" \
  -f Dockerfile.cjk \
  .

container_id=$(docker create "$packager_image")
trap 'docker rm -f "$container_id" >/dev/null 2>&1 || true' EXIT
rm -rf "$output_dir"
mkdir -p "$output_dir"
docker cp "$container_id:/out/." "$output_dir/"
docker rm "$container_id" >/dev/null
trap - EXIT

rpm_path=$(find "$output_dir" -maxdepth 1 -type f -name 'libreoffice-headless-*.aarch64.rpm' -print -quit)
[ -n "$rpm_path" ] || { echo 'RPM artifact not found' >&2; exit 1; }
sh tests/test-cjk-rpm.sh "$rpm_path"
