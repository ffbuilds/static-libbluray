# syntax=docker/dockerfile:1

# bump: libbluray /LIBBLURAY_VERSION=([\d.]+)/ https://code.videolan.org/videolan/libbluray.git|*
# bump: libbluray after ./hashupdate Dockerfile LIBBLURAY $LATEST
# bump: libbluray link "ChangeLog" https://code.videolan.org/videolan/libbluray/-/blob/master/ChangeLog
ARG LIBBLURAY_VERSION=1.3.3
ARG LIBBLURAY_URL="https://code.videolan.org/videolan/libbluray/-/archive/$LIBBLURAY_VERSION/libbluray-$LIBBLURAY_VERSION.tar.gz"
ARG LIBBLURAY_SHA256=b29ead1050c8a75729eef645d1d94c112845bbce7cf507cad7bc8edf4d04ebe7

# Must be specified
ARG ALPINE_VERSION

# Can be specified as anything@sha256:<hash>
ARG LIBXML2_VERSION=main

FROM alpine:${ALPINE_VERSION} AS base

FROM ghcr.io/ffbuilds/static-libxml2-alpine_${ALPINE_VERSION}:${LIBXML2_VERSION} AS libxml2

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
COPY --from=libxml2 /usr/local/lib/pkgconfig/libxml-2.0.pc /usr/local/lib/pkgconfig/libxml-2.0.pc
COPY --from=libxml2 /usr/local/lib/libxml2.a /usr/local/lib/libxml2.a
COPY --from=libxml2 /usr/local/include/libxml2/ /usr/local/include/libxml2/
COPY --from=download /tmp/libbluray/ /tmp/libbluray/
ARG ALPINE_VERSION
WORKDIR /tmp/libbluray
RUN \
  case ${ALPINE_VERSION} in \
    edge) \
      # libbluray fails on edge with freetype enabled
      # https://gist.github.com/binoculars/a97a45b2ad32a8289a302fd340143f93
      config_opts="--without-freetype" \
    ;; \
    *) \
      apk_pkgs="freetype-dev freetype-static fontconfig-dev fontconfig-static" \
    ;; \
  esac && \
  apk add --no-cache --virtual build \
    build-base autoconf automake libtool pkgconf ${apk_pkgs} && \
  autoreconf -fiv && \
  ./configure \
    --with-pic \
    --disable-doxygen-doc \
    --disable-doxygen-dot \
    --enable-static \
    --disable-shared \
    --disable-examples \
    --disable-bdjava-jar \
    ${config_opts} \
  && \
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
