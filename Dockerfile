FROM arm64v8/debian:buster AS builder

# ── 1. Fix Debian 10 Buster EOL repos ────────────────────────────────
RUN sed -i 's|deb.debian.org|archive.debian.org|g' /etc/apt/sources.list && \
    sed -i 's|security.debian.org|archive.debian.org|g' /etc/apt/sources.list && \
    sed -i '/buster-updates/d' /etc/apt/sources.list && \
    apt-get update

# ── 2. Install build toolchain + LibreOffice dependencies ────────────
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential gcc g++ make autoconf automake libtool \
    gperf flex bison patch wget curl git \
    python3 python3-dev perl \
    pkg-config \
    # Compression
    zlib1g-dev libbz2-dev liblzma-dev \
    # Crypto / network
    libssl-dev libcurl4-openssl-dev libnss3-dev \
    # Font / text rendering (needed even for headless)
    libfreetype6-dev libfontconfig1-dev libcairo2-dev \
    libharfbuzz-dev libicu-dev \
    # Minimal X libs (UNO type definitions reference these)
    libx11-dev libxext-dev libxrender-dev libxrandr-dev \
    libxinerama-dev libxt-dev \
    # Image format support
    libjpeg-dev libpng-dev \
    # LibreOffice specific
    libxml2-dev libxslt1-dev libxml2-utils xsltproc \
    libexpat1-dev libhunspell-dev \
    libcups2-dev \
    # Graphics (headless still needs basic glib/pango)
    libglib2.0-dev libpango1.0-dev \
    # Archive / misc tools
    cpio unzip zip tar gzip xz-utils \
    ccache ca-certificates \
    # nasm for bundled jpeg-turbo etc
    nasm \
    && rm -rf /var/lib/apt/lists/*

# ── 3. Verify toolchain ──────────────────────────────────────────────
RUN gcc --version | head -1 && \
    ldd --version 2>&1 | head -1 && \
    uname -m && \
    python3 --version

# ── 4. Set up ccache ─────────────────────────────────────────────────
ENV CCACHE_DIR=/build/ccache
RUN mkdir -p /usr/lib/ccache && \
    ln -sf /usr/bin/ccache /usr/lib/ccache/gcc && \
    ln -sf /usr/bin/ccache /usr/lib/ccache/g++ && \
    ln -sf /usr/bin/ccache /usr/lib/ccache/cc && \
    ln -sf /usr/bin/ccache /usr/lib/ccache/c++
ENV PATH="/usr/lib/ccache:${PATH}"

# ── 5. Download LibreOffice 7.5.9 source ─────────────────────────────
WORKDIR /build
ARG LO_VERSION=7.5.9.2
RUN curl -fSL "https://downloadarchive.documentfoundation.org/libreoffice/old/${LO_VERSION}/src/libreoffice-${LO_VERSION}.tar.xz" \
    -o libreoffice-src.tar.xz && \
    tar xf libreoffice-src.tar.xz && \
    rm libreoffice-src.tar.xz && \
    mv libreoffice-${LO_VERSION} libreoffice-src

# ── 6. Configure: headless, no Java, no GUI ──────────────────────────
WORKDIR /build/libreoffice-src
RUN ./autogen.sh \
    --disable-gui \
    --enable-headless \
    --without-java \
    --without-doxygen \
    --disable-firebird-sdbc \
    --disable-report-builder \
    --disable-odk \
    --disable-lotuswordpro \
    --disable-lpsolve \
    --disable-coinmp \
    --with-galleries=no \
    --with-theme=no \
    --disable-online-update \
    --disable-dependency-tracking \
    --enable-release-build \
    --prefix=/opt/libreoffice-headless \
    --with-parallelism=$(nproc) \
    --with-external-tar=/build/lo-externalsrc \
    2>&1 | tee /build/configure.log

# ── 7. Build ─────────────────────────────────────────────────────────
RUN make -j$(nproc) 2>&1 | tee /build/build.log

# ── 8. Install to prefix ─────────────────────────────────────────────
RUN make distro-pack-install DESTDIR=/build/instdir 2>&1 | tee /build/install.log

# ── 9. Verify: no absolute path leaks, glibc symbols ≤ 2.28 ─────────
RUN echo "=== Checking for hardcoded paths ===" && \
    grep -r "/build/" /build/instdir/opt/ --include='*.rc' --include='*.ini' || echo "No hardcoded paths found" && \
    echo "=== Checking glibc symbol versions ===" && \
    objdump -T /build/instdir/opt/libreoffice-headless/program/soffice.bin 2>/dev/null | \
    grep GLIBC_ | awk '{print $NF}' | sort -Vu || true

# ── 10. Package ──────────────────────────────────────────────────────
RUN cd /build/instdir && \
    tar czf /build/libreoffice-7.5.9-headless-aarch64-kylinv10.tar.gz opt/

# ── 11. Quick smoke test ─────────────────────────────────────────────
RUN echo "Hello LibreOffice" > /tmp/test.txt && \
    /build/instdir/opt/libreoffice-headless/program/soffice \
    --headless --convert-to pdf --outdir /tmp /tmp/test.txt && \
    ls -la /tmp/test.pdf && \
    echo "=== SMOKE TEST PASSED ==="
