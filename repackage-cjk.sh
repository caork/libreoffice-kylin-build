#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <original.rpm> <font-dir> <output-dir>" >&2
  exit 2
fi

original_rpm=$1
font_dir=$2
output_dir=$3
version=24.2.5.2
release=4
package_name=libreoffice-headless
font_target='opt/libreoffice-headless/lib/libreoffice/share/fonts/truetype'
runtime_root='opt/libreoffice-headless'
font_files=(
  NotoSansCJKsc-Regular.otf
  NotoSansCJKsc-Bold.otf
  NotoSerifCJKsc-Regular.otf
  NotoSerifCJKsc-Bold.otf
)

for input in "$original_rpm" "$font_dir/Noto-CJK-LICENSE" \
  "${font_files[@]/#/$font_dir/}"; do
  [ -f "$input" ] || { echo "required input is missing: $input" >&2; exit 1; }
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
rpm_root="$work_dir/rpm-root"
top_dir="$work_dir/rpmbuild"
mkdir -p "$rpm_root" "$top_dir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$output_dir"

(cd "$rpm_root" && rpm2cpio "$original_rpm" | cpio -idm --quiet)

inject_fonts() {
  local root=$1
  local target="$root/$font_target"
  local config="$target/fc_local.conf"
  local replacement="$config.repackaged"

  [ -f "$config" ] || { echo "LibreOffice fontconfig file missing: $config" >&2; exit 1; }
  install -d "$target"
  for font_file in "${font_files[@]}"; do
    install -m 0644 "$font_dir/$font_file" "$target/"
  done
  install -m 0644 "$font_dir/Noto-CJK-LICENSE" "$target/"
  head -n -1 "$config" > "$replacement"
  cat /usr/local/share/libreoffice-cjk/cjk-font-aliases.xml >> "$replacement"
  printf '%s\n' '</fontconfig>' >> "$replacement"
  mv "$replacement" "$config"
}

inject_fonts "$rpm_root"

install -d "$rpm_root/$runtime_root/etc/fonts" "$rpm_root/$runtime_root/bin" \
  "$rpm_root/usr/local/bin"
install -m 0644 /usr/local/share/libreoffice-cjk/fonts.conf \
  "$rpm_root/$runtime_root/etc/fonts/fonts.conf"
rm -f "$rpm_root/$runtime_root/bin/soffice"
install -m 0755 /usr/local/share/libreoffice-cjk/soffice \
  "$rpm_root/$runtime_root/bin/soffice"
ln -sfn /opt/libreoffice-headless/bin/soffice "$rpm_root/usr/local/bin/soffice"
ln -sfn /opt/libreoffice-headless/bin/soffice "$rpm_root/usr/local/bin/libreoffice"

rm -rf "$rpm_root/usr/lib/.build-id"
printf '%s\n' /opt/libreoffice-headless /usr/local/bin/libreoffice \
  /usr/local/bin/soffice > "$top_dir/SOURCES/files.list"
cp -a "$rpm_root/." "$top_dir/SOURCES/payload"

cat > "$top_dir/SPECS/${package_name}.spec" <<SPEC
%global _build_id_links none
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
- Bundle Noto CJK fallback fonts and a restart-aware headless launcher.
SPEC

rpmbuild --define "_topdir $top_dir" --target aarch64 -bb "$top_dir/SPECS/${package_name}.spec"
rpm_output=$(find "$top_dir/RPMS" -type f -name "${package_name}-${version}-${release}*.aarch64.rpm" -print -quit)
[ -n "$rpm_output" ] || { echo 'RPM build did not produce the expected artifact' >&2; exit 1; }
cp "$rpm_output" "$output_dir/${package_name}-${version}-${release}.aarch64.rpm"

(cd "$output_dir" && sha256sum "${package_name}-${version}-${release}.aarch64.rpm") \
  > "$output_dir/SHA256SUMS"
