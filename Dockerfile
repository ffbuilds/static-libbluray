
# bump: libbluray /LIBBLURAY_VERSION=([\d.]+)/ https://code.videolan.org/videolan/libbluray.git|*
# bump: libbluray after ./hashupdate Dockerfile LIBBLURAY $LATEST
# bump: libbluray link "ChangeLog" https://code.videolan.org/videolan/libbluray/-/blob/master/ChangeLog
ARG LIBBLURAY_VERSION=1.3.3
ARG LIBBLURAY_URL="https://code.videolan.org/videolan/libbluray/-/archive/$LIBBLURAY_VERSION/libbluray-$LIBBLURAY_VERSION.tar.gz"
ARG LIBBLURAY_SHA256=b29ead1050c8a75729eef645d1d94c112845bbce7cf507cad7bc8edf4d04ebe7

# Must be specified
ARG ALPINE_VERSION

FROM alpine:${ALPINE_VERSION} AS base

FROM base AS download
ARG LIBBLURAY_URL
ARG LIBBLURAY_SHA256
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    coreutils wget tar git && \
  wget $WGET_OPTS -O libbluray.tar.gz "$LIBBLURAY_URL" && \
  echo "$LIBBLURAY_SHA256  libbluray.tar.gz" | sha256sum --status -c - && \
  mkdir libbluray && \
  tar xf libbluray.tar.gz -C libbluray --strip-components=1 && \
  cd libbluray && \
  git clone https://code.videolan.org/videolan/libudfread.git contrib/libudfread && \
  rm /tmp/libbluray.tar.gz && \
  apk del download

FROM base AS build
COPY --from=download /tmp/libbluray/ /tmp/libbluray/
WORKDIR /tmp/libbluray
RUN \
  apk add --no-cache --virtual build \
    build-base autoconf automake libtool pkgconf \
    libxml2-dev \
    freetype freetype-dev freetype-static \
    fontconfig-dev fontconfig-static && \
  autoreconf -fiv && \
  ./configure --with-pic --disable-doxygen-doc --disable-doxygen-dot --enable-static --disable-shared --disable-examples --disable-bdjava-jar && \
  make -j$(nproc) install && \
  # Sanity tests
  pkg-config --exists --modversion --path libbluray && \
  ar -t /usr/local/lib/libbluray.a && \
  readelf -h /usr/local/lib/libbluray.a && \
  # Cleanup
  apk del build

FROM scratch
ARG LIBBLURAY_VERSION
COPY --from=build /usr/local/lib/pkgconfig/libbluray.pc /usr/local/lib/pkgconfig/libbluray.pc
COPY --from=build /usr/local/lib/libbluray.a /usr/local/lib/libbluray.a
COPY --from=build /usr/local/include/libbluray/ /usr/local/include/libbluray/
