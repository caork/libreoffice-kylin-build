#!/bin/sh
set -eu

rpm_path=${1:?usage: $0 <rpm-path> [work-dir] [packager-image]}
work_dir=${2:-/tmp/libreoffice-cjk-rpm-test}
packager_image=${3:-libreoffice-cjk-packager:latest}
rpm_dir=$(cd "$(dirname "$rpm_path")" && pwd)
rpm_file=$(basename "$rpm_path")
fixture_dir=$(cd "$(dirname "$0")/fixtures" && pwd)

rm -rf "$work_dir"
mkdir -p "$work_dir/root" "$work_dir/docx" "$work_dir/pptx"
cp "$fixture_dir/chinese-font-test.docx" "$fixture_dir/chinese-font-test.pptx" "$work_dir/"

docker run --rm \
  -e RPM_FILE="$rpm_file" \
  -v "$rpm_dir:/pkg:ro" \
  -v "$work_dir:/work" \
  "$packager_image" \
  sh -ec '
    rpm -qpi "/pkg/$RPM_FILE"
    cd /work/root
    rpm2cpio "/pkg/$RPM_FILE" | cpio -idm --quiet
    test -x opt/libreoffice-headless/bin/soffice
    test -f opt/libreoffice-headless/etc/fonts/fonts.conf
    test "$(find opt/libreoffice-headless/lib/libreoffice/share/fonts/truetype -name "Noto*CJKsc-*.otf" | wc -l)" -eq 4
  '

docker run --rm --platform linux/arm64 \
  -e HOME=/tmp \
  -v "$work_dir/root/opt:/opt:ro" \
  -v "$work_dir:/work" \
  arm64v8/debian:bookworm-slim \
  sh -ec '
    /opt/libreoffice-headless/bin/soffice --headless --version
    /opt/libreoffice-headless/bin/soffice --headless --convert-to pdf --outdir /work/docx /work/chinese-font-test.docx
    /opt/libreoffice-headless/bin/soffice --headless --convert-to pdf --outdir /work/pptx /work/chinese-font-test.pptx
    test -s /work/docx/chinese-font-test.pdf
    test -s /work/pptx/chinese-font-test.pdf
    grep -a -i -q Noto /work/docx/chinese-font-test.pdf
    grep -a -i -q Noto /work/pptx/chinese-font-test.pdf
  '

ls -lh "$work_dir/docx/chinese-font-test.pdf" "$work_dir/pptx/chinese-font-test.pdf"
