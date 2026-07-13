#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <original.tar.gz> <original.rpm> <font-dir> <output-dir>" >&2
  exit 2
fi

original_tar=$1
original_rpm=$2
font_dir=$3
output_dir=$4
version=24.2.5.2
release=2
package_name=libreoffice-headless
font_target='opt/libreoffice-headless/lib/libreoffice/share/fonts/truetype'

for input in "$original_tar" "$original_rpm" \
  "$font_dir/NotoSansCJK-Regular.ttc" "$font_dir/NotoSansCJK-Bold.ttc" \
  "$font_dir/NotoSerifCJK-Regular.ttc" "$font_dir/NotoSerifCJK-Bold.ttc" \
  "$font_dir/Noto-CJK-LICENSE"; do
  [ -f "$input" ] || { echo "required input is missing: $input" >&2; exit 1; }
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
tar_root="$work_dir/tar-root"
rpm_root="$work_dir/rpm-root"
top_dir="$work_dir/rpmbuild"
mkdir -p "$tar_root" "$rpm_root" "$top_dir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$output_dir"

tar xzf "$original_tar" -C "$tar_root"
(cd "$rpm_root" && rpm2cpio "$original_rpm" | cpio -idm --quiet)

inject_fonts() {
  local root=$1
  local target="$root/$font_target"
  local config="$target/fc_local.conf"
  local replacement="$config.repackaged"

  [ -f "$config" ] || { echo "LibreOffice fontconfig file missing: $config" >&2; exit 1; }
  install -d "$target"
  install -m 0644 "$font_dir"/Noto*CJK-*.ttc "$target/"
  install -m 0644 "$font_dir/Noto-CJK-LICENSE" "$target/"
  head -n -1 "$config" > "$replacement"
  cat /usr/local/share/libreoffice-cjk/cjk-font-aliases.xml >> "$replacement"
  printf '%s\n' '</fontconfig>' >> "$replacement"
  mv "$replacement" "$config"
}

inject_fonts "$tar_root"
inject_fonts "$rpm_root"

tar_output="$output_dir/libreoffice-${version}-headless-aarch64-cjk.tar.gz"
tar -C "$tar_root" -czf "$tar_output" opt

find "$rpm_root" -mindepth 1 -printf '/%P\n' | sort > "$top_dir/SOURCES/files.list"
cp -a "$rpm_root/." "$top_dir/SOURCES/payload"

cat > "$top_dir/SPECS/${package_name}.spec" <<SPEC
Name:           ${package_name}
Version:        ${version}
Release:        ${release}%{?dist}
Summary:        LibreOffice 24.2.5.2 headless with bundled Noto CJK fallback fonts
License:        MPL-2.0 AND OFL-1.1
AutoReqProv:    no

%description
ARM64 LibreOffice headless runtime with Noto CJK fallback fonts bundled for
reliable DOCX and PPTX conversion on systems without Chinese fonts.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a %{_sourcedir}/payload/. %{buildroot}/

%files -f %{_sourcedir}/files.list

%changelog
* Mon Jul 13 2026 caork - ${version}-${release}
- Bundle Noto CJK fallback fonts for Chinese document conversion.
SPEC

rpmbuild --define "_topdir $top_dir" --target aarch64 -bb "$top_dir/SPECS/${package_name}.spec"
rpm_output=$(find "$top_dir/RPMS" -type f -name "${package_name}-${version}-${release}*.aarch64.rpm" -print -quit)
[ -n "$rpm_output" ] || { echo 'RPM build did not produce the expected artifact' >&2; exit 1; }
cp "$rpm_output" "$output_dir/${package_name}-${version}-${release}.aarch64.rpm"

sha256sum "$tar_output" "$output_dir/${package_name}-${version}-${release}.aarch64.rpm" \
  > "$output_dir/SHA256SUMS"
