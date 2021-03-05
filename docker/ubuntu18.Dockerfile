# ==============================================================================
# Copyright (C) 2018-2021 Intel Corporation
#
# SPDX-License-Identifier: MIT
# ==============================================================================

ARG http_proxy
ARG https_proxy
ARG DOCKER_PRIVATE_REGISTRY

# Install OpenVINO™ Toolkit
FROM ${DOCKER_PRIVATE_REGISTRY}ubuntu:18.04 as ov-build
WORKDIR /root
USER root

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

ENV HTTP_PROXY=${http_proxy}
ENV HTTPS_PROXY=${https_proxy}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y -q --no-install-recommends cpio \
    pciutils \
    wget

ARG OPENVINO_URL
ARG OpenVINO_VERSION

ADD ${OPENVINO_URL} .

RUN tar -xzf *.tgz \
    && cd l_openvino_toolkit*p_${OpenVINO_VERSION} \
    && sed -i 's@rpm -Uvh https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm@rpm -Uvh https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm || true@g' ./install_openvino_dependencies.sh \
    && ./install_openvino_dependencies.sh -y \
    && OpenVINO_YEAR="$(echo ${OpenVINO_VERSION} | cut -d "." -f 1)" \
    && sed -i 's/decline/accept/g' silent.cfg \
    && ./install.sh -s silent.cfg \
    && ln --symbolic /opt/intel/openvino_${OpenVINO_VERSION}/ /opt/intel/openvino

# Remove GStreamer from dldt
RUN rm -r /opt/intel/openvino_${OpenVINO_VERSION}/data_processing/gstreamer

# Build GStreamer and other plugins
FROM ${DOCKER_PRIVATE_REGISTRY}ubuntu:18.04 as gst-build
ENV HOME=/home
WORKDIR ${HOME}

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

ENV HTTP_PROXY=${http_proxy}
ENV HTTPS_PROXY=${https_proxy}

# COMMON BUILD TOOLS
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends \
        cmake \
        build-essential \
        automake \
        autoconf \
        make \
        git \
        wget \
        pciutils \
        cpio \
        libtool \
        lsb-release \
        ca-certificates \
        pkg-config \
        bison \
        flex \
        libcurl4-gnutls-dev \
        zlib1g-dev \
        nasm \
        yasm \
        xorg-dev \
        libgl1-mesa-dev \
        openbox \
        python3 \
        python3-pip \
        python3-setuptools && \
    rm -rf /var/lib/apt/lists/*


ARG PACKAGE_ORIGIN="https://gstreamer.freedesktop.org"

ARG PREFIX=/
ARG LIBDIR=lib/
ARG LIBEXECDIR=bin/

ARG GST_VERSION=1.18.3
ARG BUILD_TYPE_MESON=release

ENV GSTREAMER_LIB_DIR=${PREFIX}/${LIBDIR}
ENV LIBRARY_PATH=${GSTREAMER_LIB_DIR}:${GSTREAMER_LIB_DIR}/gstreamer-1.0:${LIBRARY_PATH}
ENV LD_LIBRARY_PATH=${LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${GSTREAMER_LIB_DIR}/pkgconfig
ENV PATCHES_ROOT=${HOME}/build/src/patches
RUN mkdir -p ${PATCHES_ROOT}

# GStreamer core
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install --no-install-recommends -q -y \
        libglib2.0-dev \
        libgmp-dev \
        libgsl-dev \
        gobject-introspection \
        libcap-dev \
        libcap2-bin \
        gettext \
        libgirepository1.0-dev && \
    rm -rf /var/lib/apt/lists/* && \
    pip3 install --no-cache-dir meson ninja

ARG MESON_GST_TESTS=disabled

ARG GST_REPO=https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-${GST_VERSION}.tar.xz
RUN wget ${GST_REPO} -O build/src/gstreamer-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gstreamer-${GST_VERSION}.tar.xz && \
    cd gstreamer-${GST_VERSION} && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig meson \
    -Dexamples=disabled \
    -Dtests=${MESON_GST_TESTS} \
    -Dbenchmarks=disabled \
    -Dgtk_doc=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# ORC Acceleration
ARG GST_ORC_VERSION=0.4.31
ARG GST_ORC_REPO=https://gstreamer.freedesktop.org/src/orc/orc-${GST_ORC_VERSION}.tar.xz
RUN wget ${GST_ORC_REPO} -O build/src/orc-${GST_ORC_VERSION}.tar.xz
RUN tar xvf build/src/orc-${GST_ORC_VERSION}.tar.xz && \
    cd orc-${GST_ORC_VERSION} && \
    meson \
    -Dexamples=disabled \
    -Dtests=${MESON_GST_TESTS} \
    -Dbenchmarks=disabled \
    -Dgtk_doc=disabled \
    -Dorc-test=${MESON_GST_TESTS} \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# GStreamer Base plugins
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends \
    libx11-dev \
    iso-codes \
    libegl1-mesa-dev \
    libgles2-mesa-dev \
    libgl-dev \
    gudev-1.0 \
    libtheora-dev \
    libcdparanoia-dev \
    libpango1.0-dev \
    libgbm-dev \
    libasound2-dev \
    libjpeg-dev \
    libvisual-0.4-dev \
    libxv-dev \
    libopus-dev \
    libgraphene-1.0-dev \
    libvorbis-dev && \
    rm -rf /var/lib/apt/lists/*

# Build the gstreamer plugin base
ARG GST_PLUGIN_BASE_REPO=https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-${GST_VERSION}.tar.xz
RUN wget ${GST_PLUGIN_BASE_REPO} -O build/src/gst-plugins-base-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gst-plugins-base-${GST_VERSION}.tar.xz && \
    cd gst-plugins-base-${GST_VERSION} && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=disabled \
    -Dtests=${MESON_GST_TESTS} \
    -Dgtk_doc=disabled \
    -Dnls=disabled \
    -Dgl=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# GStreamer Good plugins
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends \
    libbz2-dev \
    libv4l-dev \
    libaa1-dev \
    libflac-dev \
    libgdk-pixbuf2.0-dev \
    libmp3lame-dev \
    libcaca-dev \
    libdv4-dev \
    libmpg123-dev \
    libraw1394-dev \
    libavc1394-dev \
    libiec61883-dev \
    libpulse-dev \
    libsoup2.4-dev \
    libspeex-dev \
    libtag-extras-dev \
    libtwolame-dev \
    libwavpack-dev && \
    rm -rf /var/lib/apt/lists/*

ARG GST_PLUGIN_GOOD_REPO=https://gstreamer.freedesktop.org/src/gst-plugins-good/gst-plugins-good-${GST_VERSION}.tar.xz

RUN wget ${GST_PLUGIN_GOOD_REPO} -O build/src/gst-plugins-good-${GST_VERSION}.tar.xz
RUN mkdir gst-plugins-good-${GST_VERSION} && \
    tar xvf build/src/gst-plugins-good-${GST_VERSION}.tar.xz && \
    cd gst-plugins-good-${GST_VERSION}  && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=disabled \
    -Dtests=${MESON_GST_TESTS} \
    -Dgtk_doc=disabled \
    -Dnls=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# GStreamer Bad plugins
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends \
    libbluetooth-dev \
    libusb-1.0.0-dev \
    libass-dev \
    libbs2b-dev \
    libchromaprint-dev \
    liblcms2-dev \
    libssh2-1-dev \
    libdc1394-22-dev \
    libdirectfb-dev \
    libssh-dev \
    libdca-dev \
    libfaac-dev \
    libfdk-aac-dev \
    flite1-dev \
    libfluidsynth-dev \
    libgme-dev \
    libgsm1-dev \
    nettle-dev \
    libkate-dev \
    liblrdf0-dev \
    libde265-dev \
    libmjpegtools-dev \
    libmms-dev \
    libmodplug-dev \
    libmpcdec-dev \
    libneon27-dev \
    libopenal-dev \
    libopenexr-dev \
    libopenjp2-7-dev \
    libopenmpt-dev \
    libopenni2-dev \
    libdvdnav-dev \
    librtmp-dev \
    librsvg2-dev \
    libsbc-dev \
    libsndfile1-dev \
    libsoundtouch-dev \
    libspandsp-dev \
    libsrtp2-dev \
    libzvbi-dev \
    libvo-aacenc-dev \
    libvo-amrwbenc-dev \
    libwebrtc-audio-processing-dev \
    libwebp-dev \
    libwildmidi-dev \
    libzbar-dev \
    libnice-dev \
    libxkbcommon-dev && \
    rm -rf /var/lib/apt/lists/*

# Uninstalled dependencies: opencv, opencv4, libmfx(waiting intelMSDK), wayland(low version), vdpau
ARG GST_PLUGIN_BAD_REPO=https://gstreamer.freedesktop.org/src/gst-plugins-bad/gst-plugins-bad-${GST_VERSION}.tar.xz

# download gst-plugins-bad
RUN wget ${GST_PLUGIN_BAD_REPO} -O build/src/gst-plugins-bad-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gst-plugins-bad-${GST_VERSION}.tar.xz &&\
    cd gst-plugins-bad-${GST_VERSION} && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=disabled \
    -Dtests=${MESON_GST_TESTS} \
    -Ddoc=disabled \
    -Dnls=disabled \
    -Dx265=disabled \
    -Dyadif=disabled \
    -Dresindvd=disabled \
    -Dmplex=disabled \
    -Ddts=disabled \
    -Dofa=disabled \
    -Dfaad=disabled \
    -Dmpeg2enc=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# Build the gstreamer plugin ugly set
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends \
    libmpeg2-4-dev \
    libopencore-amrnb-dev \
    libopencore-amrwb-dev \
    liba52-0.7.4-dev \
    && rm -rf /var/lib/apt/lists/*

ARG GST_PLUGIN_UGLY_REPO=https://gstreamer.freedesktop.org/src/gst-plugins-ugly/gst-plugins-ugly-${GST_VERSION}.tar.xz

RUN wget ${GST_PLUGIN_UGLY_REPO} -O build/src/gst-plugins-ugly-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gst-plugins-ugly-${GST_VERSION}.tar.xz && \
    cd gst-plugins-ugly-${GST_VERSION}  && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=disabled \
    -Dtests=${MESON_GST_TESTS} \
    -Dgtk_doc=disabled \
    -Dnls=disabled \
    -Dcdio=disabled \
    -Dsid=disabled \
    -Dmpeg2dec=disabled \
    -Ddvdread=disabled \
    -Da52dec=disabled \
    -Dx264=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# FFmpeg
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends bzip2

RUN mkdir ffmpeg_sources && cd ffmpeg_sources && \
    wget -O - https://www.nasm.us/pub/nasm/releasebuilds/2.14.02/nasm-2.14.02.tar.bz2 | tar xj && \
    cd nasm-2.14.02 && \
    ./autogen.sh && \
    ./configure --prefix=${PREFIX} --bindir="${PREFIX}/bin" && \
    make && make install

RUN wget https://ffmpeg.org/releases/ffmpeg-4.3.2.tar.gz -O build/src/ffmpeg-4.3.2.tar.gz
RUN cd ffmpeg_sources && \
    tar xvf /home/build/src/ffmpeg-4.3.2.tar.gz && \
    cd ffmpeg-4.3.2 && \
    PATH="${PREFIX}/bin:$PATH" PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig" \
    ./configure \
    --disable-gpl \
    --enable-pic \
    --disable-shared \
    --enable-static \
    --prefix=${PREFIX} \
    --extra-cflags="-I${PREFIX}/include" \
    --extra-ldflags="-L${PREFIX}/lib" \
    --extra-libs=-lpthread \
    --extra-libs=-lm \
    --bindir="${PREFIX}/bin" \
    --disable-vaapi && \
    make -j $(nproc) && \
    make install

# Build gst-libav
ARG GST_PLUGIN_LIBAV_REPO=https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-${GST_VERSION}.tar.xz
RUN wget ${GST_PLUGIN_LIBAV_REPO} -O build/src/gst-libav-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gst-libav-${GST_VERSION}.tar.xz && \
    cd gst-libav-${GST_VERSION} && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=${MESON_GST_TESTS} \
    -Dtests=${MESON_GST_TESTS} \
    -Dgtk_doc=disabled \
    -Dnls=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# Build Intel(R) Media SDK
ARG MSDK_REPO=https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-20.5.1/MediaStack.tar.gz
RUN wget  -O - ${MSDK_REPO} | tar xz -C /home/build/ && \
    cd /home/build/MediaStack && \
    cp -a opt/. /opt/ && \
    cp -a etc/. /etc/ && \
    ldconfig

ENV PKG_CONFIG_PATH=/opt/intel/mediasdk/lib64/pkgconfig:${PKG_CONFIG_PATH}
ENV LIBRARY_PATH=/opt/intel/mediasdk/lib64:${LIBRARY_PATH}
ENV LD_LIBRARY_PATH=/opt/intel/mediasdk/lib64:${LD_LIBRARY_PATH}
ENV LIBVA_DRIVERS_PATH=/opt/intel/mediasdk/lib64
ENV LIBVA_DRIVER_NAME=iHD

# Build gstreamer plugin vaapi
ARG GST_PLUGIN_VAAPI_REPO=https://gstreamer.freedesktop.org/src/gstreamer-vaapi/gstreamer-vaapi-${GST_VERSION}.tar.xz

ENV GST_VAAPI_ALL_DRIVERS=1

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y -q --no-install-recommends \
        libva-dev \
        libxrandr-dev \
        libudev-dev \
        libgtk-3-dev && \
    rm -rf /var/lib/apt/lists/*

# download gstreamer-vaapi
RUN wget ${GST_PLUGIN_VAAPI_REPO} -O build/src/gstreamer-vaapi-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gstreamer-vaapi-${GST_VERSION}.tar.xz

# download gstreamer-vaapi patch
ARG GSTREAMER_VAAPI_PATCH_URL=https://raw.githubusercontent.com/opencv/gst-video-analytics/master/patches/gstreamer-vaapi/vasurface_qdata.patch
RUN wget ${GSTREAMER_VAAPI_PATCH_URL} -O ${PATCHES_ROOT}/gstreamer-vaapi.patch

# put gstreamer-vaapi license along with the patch
RUN mkdir ${PATCHES_ROOT}/gstreamer_vaapi_patch_license && \
    cp gstreamer-vaapi-${GST_VERSION}/COPYING.LIB ${PATCHES_ROOT}/gstreamer_vaapi_patch_license/LICENSE

RUN cd gstreamer-vaapi-${GST_VERSION} && \
    wget -O - ${GSTREAMER_VAAPI_PATCH_URL} | git apply && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=${MESON_GST_TESTS} \
    -Dtests=${MESON_GST_TESTS} \
    -Dgtk_doc=disabled \
    -Dnls=disabled \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

# gst-python
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install --no-install-recommends -y \
    python-gi-dev \
    python3-dev && \
    rm -rf /var/lib/apt/lists/*

ARG GST_PYTHON_REPO=https://gstreamer.freedesktop.org/src/gst-python/gst-python-${GST_VERSION}.tar.xz
RUN wget ${GST_PYTHON_REPO} -O build/src/gst-python-${GST_VERSION}.tar.xz
RUN tar xvf build/src/gst-python-${GST_VERSION}.tar.xz && \
    cd gst-python-${GST_VERSION} && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dpython=python3 \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

ENV GI_TYPELIB_PATH=${GSTREAMER_LIB_DIR}/girepository-1.0
ENV PYTHONPATH=${PREFIX}/lib/python3.6/site-packages:${PYTHONPATH}

ARG GST_RTSP_SERVER_REPO=https://gstreamer.freedesktop.org/src/gst-rtsp-server/gst-rtsp-server-${GST_VERSION}.tar.xz
RUN wget ${GST_RTSP_SERVER_REPO} -O build/src/gst-rtsp-server-${GST_VERSION}.tar.xz
RUN tar xf build/src/gst-rtsp-server-${GST_VERSION}.tar.xz && \
    cd gst-rtsp-server-${GST_VERSION} && \
    PKG_CONFIG_PATH=$PWD/build/pkgconfig:${PKG_CONFIG_PATH} meson \
    -Dexamples=${MESON_GST_TESTS} \
    -Dtests=${MESON_GST_TESTS} \
    -Dpackage-origin="${PACKAGE_ORIGIN}" \
    --buildtype=${BUILD_TYPE_MESON} \
    --prefix=${PREFIX} \
    --libdir=${LIBDIR} \
    --libexecdir=${LIBEXECDIR} \
    build/ && \
    ninja -C build && \
    DESTDIR=/home/build meson install -C build/ && \
    meson install -C build/

ARG ENABLE_PAHO_INSTALLATION=true
ARG PAHO_VER=1.3.8
ARG PAHO_REPO=https://github.com/eclipse/paho.mqtt.c/archive/v${PAHO_VER}.tar.gz
RUN if [ "$ENABLE_PAHO_INSTALLATION" = "true" ] ; then \
    wget -O - ${PAHO_REPO} | tar -xz && \
    cd paho.mqtt.c-${PAHO_VER} && \
    make && \
    make install && \
    cp build/output/libpaho-mqtt3c.so.1.3 /home/build/${LIBDIR}/ && \
    cp build/output/libpaho-mqtt3cs.so.1.3 /home/build/${LIBDIR}/ && \
    cp build/output/libpaho-mqtt3a.so.1.3 /home/build/${LIBDIR}/ && \
    cp build/output/libpaho-mqtt3as.so.1.3 /home/build/${LIBDIR}/ && \
    cp build/output/paho_c_version /home/build/${LIBEXECDIR}/ && \
    cp build/output/samples/paho_c_pub /home/build/${LIBEXECDIR}/ && \
    cp build/output/samples/paho_c_sub /home/build/${LIBEXECDIR}/ && \
    cp build/output/samples/paho_cs_pub /home/build/${LIBEXECDIR}/ && \
    cp build/output/samples/paho_cs_sub /home/build/${LIBEXECDIR}/ && \
    chmod 644 /home/build/${LIBDIR}/libpaho-mqtt3c.so.1.3 && \
    chmod 644 /home/build/${LIBDIR}/libpaho-mqtt3cs.so.1.3 && \
    chmod 644 /home/build/${LIBDIR}/libpaho-mqtt3a.so.1.3 && \
    chmod 644 /home/build/${LIBDIR}/libpaho-mqtt3as.so.1.3 && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3c.so.1.3 /home/build/${LIBDIR}/libpaho-mqtt3c.so.1 && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3cs.so.1.3 /home/build/${LIBDIR}/libpaho-mqtt3cs.so.1 && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3a.so.1.3 /home/build/${LIBDIR}/libpaho-mqtt3a.so.1 && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3as.so.1.3 /home/build/${LIBDIR}/libpaho-mqtt3as.so.1 && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3c.so.1 /home/build/${LIBDIR}/libpaho-mqtt3c.so && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3cs.so.1 /home/build/${LIBDIR}/libpaho-mqtt3cs.so && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3a.so.1 /home/build/${LIBDIR}/libpaho-mqtt3a.so && \
    ln /home/build/${LIBDIR}/libpaho-mqtt3as.so.1 /home/build/${LIBDIR}/libpaho-mqtt3as.so && \
    cp src/MQTTAsync.h /home/build/${PREFIX}/include/ && \
    cp src/MQTTExportDeclarations.h /home/build/${PREFIX}/include/ && \
    cp src/MQTTClient.h /home/build/${PREFIX}/include/ && \
    cp src/MQTTClientPersistence.h /home/build/${PREFIX}/include/ && \
    cp src/MQTTProperties.h /home/build/${PREFIX}/include/ && \
    cp src/MQTTReasonCodes.h /home/build/${PREFIX}/include/ && \
    cp src/MQTTSubscribeOpts.h /home/build/${PREFIX}/include/; \
    else \
    echo "PAHO install disabled"; \
    fi

ARG ENABLE_RDKAFKA_INSTALLATION=true
ARG RDKAFKA_VER=1.6.0
ARG RDKAFKA_REPO=https://github.com/edenhill/librdkafka/archive/v${RDKAFKA_VER}.tar.gz
RUN if [ "$ENABLE_RDKAFKA_INSTALLATION" = "true" ] ; then \
        wget -O - ${RDKAFKA_REPO} | tar -xz && \
        cd librdkafka-${RDKAFKA_VER} && \
        ./configure \
            --prefix=${PREFIX} \
            --libdir=${GSTREAMER_LIB_DIR} && \
        make -j $(nproc) && \
        make install && \
        make install DESTDIR=/home/build && \
        rm /home/build/lib/librdkafka*.a && \
        rm /home/build/lib/pkgconfig/rdkafka*static.pc; \
    else \
        echo "KAFKA install disabled"; \
    fi

RUN grep -lr "prefix=/" --include="*.pc" -l /home/build/ | xargs sed -i 's#prefix=/#prefix=\${pcfiledir}\/..\/..\/#g' \
    && grep -lr "includedir=/" --include="*.pc" -l /home/build/ | xargs sed -i 's#includedir=/#includedir=\${prefix}\/#g' \
    && grep -lr "libdir=/" --include="*.pc" -l /home/build/ | xargs sed -i 's#libdir=/#libdir=\${prefix}\/#g'

#Build DL Streamer plugin
FROM ov-build
FROM gst-build

FROM ${DOCKER_PRIVATE_REGISTRY}ubuntu:18.04
LABEL Description="This is the base image for GSTREAMER & OpenVINO™ Toolkit Ubuntu 18.04 LTS"
LABEL Vendor="Intel Corporation"
WORKDIR /root

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Prerequisites
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
    libusb-1.0-0-dev libboost-all-dev libgtk2.0-dev lsb-release \
    \
    clinfo opencl-headers ocl-icd-libopencl1 libnuma1 libboost-all-dev libjson-c-dev \
    build-essential cmake ocl-icd-opencl-dev wget gcovr vim git gdb ca-certificates libssl-dev uuid-dev \
    libgirepository1.0-dev \
    python3-dev python3-wheel python3-pip python3-setuptools python-gi-dev python3-yaml \
    \
    libglib2.0-dev libgmp-dev libgsl-dev gobject-introspection libcap-dev libcap2-bin gettext \
    \
    libx11-dev iso-codes libegl1-mesa-dev libgles2-mesa-dev libgl-dev gudev-1.0 libtheora-dev libcdparanoia-dev libpango1.0-dev libgbm-dev libasound2-dev libjpeg-dev \
    libvisual-0.4-dev libxv-dev libopus-dev libgraphene-1.0-dev libvorbis-dev \
    \
    libbz2-dev libv4l-dev libaa1-dev libflac-dev libgdk-pixbuf2.0-dev libmp3lame-dev libcaca-dev libdv4-dev libmpg123-dev libraw1394-dev libavc1394-dev libiec61883-dev \
    libpulse-dev libsoup2.4-dev libspeex-dev libtag-extras-dev libtwolame-dev libwavpack-dev \
    \
    libbluetooth-dev libusb-1.0.0-dev libass-dev libbs2b-dev libchromaprint-dev liblcms2-dev libssh2-1-dev libdc1394-22-dev libdirectfb-dev libssh-dev libdca-dev \
    libfaac-dev libfdk-aac-dev flite1-dev libfluidsynth-dev libgme-dev libgsm1-dev nettle-dev libkate-dev liblrdf0-dev libde265-dev libmjpegtools-dev libmms-dev \
    libmodplug-dev libmpcdec-dev libneon27-dev libopenal-dev libopenexr-dev libopenjp2-7-dev libopenmpt-dev libopenni2-dev libdvdnav-dev librtmp-dev librsvg2-dev \
    libsbc-dev libsndfile1-dev libsoundtouch-dev libspandsp-dev libsrtp2-dev libzvbi-dev libvo-aacenc-dev libvo-amrwbenc-dev libwebrtc-audio-processing-dev libwebp-dev \
    libwildmidi-dev libzbar-dev libnice-dev libxkbcommon-dev \
    \
    libmpeg2-4-dev libopencore-amrnb-dev libopencore-amrwb-dev liba52-0.7.4-dev \
    \
    libva-dev libxrandr-dev libudev-dev \
    \
    && rm -rf /var/lib/apt/lists/* \
    && python3.6 -m pip install numpy==1.19.2 opencv-python==4.2.0.34 pytest==6.0.1

# Install
COPY --from=ov-build /opt/intel /opt/intel
COPY --from=gst-build /home/build /

# Copy MediaSDK files
RUN cp -a /MediaStack/opt/. /opt/ && \
    cp -a /MediaStack/etc/. /etc/ && \
    rm -rf /MediaStack

# Install NEO OCL drivers
RUN mkdir neo && cd neo \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-gmmlib_20.2.4_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-igc-core_1.0.4756_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-igc-opencl_1.0.4756_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-opencl_20.35.17767_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-ocloc_20.35.17767_amd64.deb \
    && dpkg -i intel*.deb

ARG PREFIX=/
ARG LIBDIR=lib/
ARG LIBEXECDIR=bin/
ARG INCLUDEDIR=include/

ENV GSTREAMER_LIB_DIR=${PREFIX}/${LIBDIR}
ENV GST_PLUGIN_SCANNER=${PREFIX}/${LIBEXECDIR}/gstreamer-1.0/gst-plugin-scanner
ENV C_INCLUDE_PATH=${PREFIX}/${INCLUDEDIR}:${C_INCLUDE_PATH}
ENV CPLUS_INCLUDE_PATH=${PREFIX}/${INCLUDEDIR}:${CPLUS_INCLUDE_PATH}

RUN echo "\
    /usr/local/lib\n\
    ${GSTREAMER_LIB_DIR}/gstreamer-1.0\n\
    /opt/intel/mediasdk/lib64\n\
    /opt/intel/openvino/inference_engine/lib/intel64\n\
    /opt/intel/openvino/inference_engine/external/tbb/lib\n\
    /opt/intel/openvino/deployment_tools/ngraph/lib\n\
    /opt/intel/openvino/inference_engine/external/hddl/lib\n\
    /opt/intel/openvino/opencv/lib/" > /etc/ld.so.conf.d/opencv-dldt-gst.conf && ldconfig

ENV GI_TYPELIB_PATH=${GSTREAMER_LIB_DIR}/girepository-1.0
ENV PYTHONPATH=${GSTREAMER_LIB_DIR}/python3.6/site-packages:${PYTHONPATH}

ENV PKG_CONFIG_PATH=${GSTREAMER_LIB_DIR}/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/opt/intel/mediasdk/lib64/pkgconfig:${PKG_CONFIG_PATH}
ENV InferenceEngine_DIR=/opt/intel/openvino/inference_engine/share
ENV OpenCV_DIR=/opt/intel/openvino/opencv/cmake
ENV LIBRARY_PATH=/opt/intel/mediasdk/lib64:/usr/lib:${GSTREAMER_LIB_DIR}:${LIBRARY_PATH}
ENV PATH=/usr/bin:${PREFIX}/${LIBEXECDIR}:/opt/intel/mediasdk/bin:${PATH}

ENV LIBVA_DRIVERS_PATH=/opt/intel/mediasdk/lib64
ENV LIBVA_DRIVER_NAME=iHD
ENV GST_VAAPI_ALL_DRIVERS=1
ENV DISPLAY=:0.0
ENV LD_LIBRARY_PATH=/usr/lib/gst-video-analytics:${LD_LIBRARY_PATH}
ENV HDDL_INSTALL_DIR=/opt/intel/openvino/inference_engine/external/hddl
ENV ngraph_DIR=/opt/intel/openvino/deployment_tools/ngraph/cmake/

# Source setupvars
RUN source /opt/intel/openvino/bin/setupvars.sh \
    && printf "\nsource /opt/intel/openvino/bin/setupvars.sh\n" >> /root/.bashrc

# Install DL Streamer
ARG OV_DLSTREAMER_DIR="/opt/intel/openvino/data_processing/dl_streamer"
ARG GST_GIT_URL="https://github.com/openvinotoolkit/dlstreamer_gst.git"

RUN git clone ${GST_GIT_URL} dl-streamer \
    && cd dl-streamer \
    && git submodule init \
    && git submodule update \
    && python3 -m pip install --no-cache-dir -r requirements.txt

ARG ENABLE_PAHO_INSTALLATION=ON
ARG ENABLE_RDKAFKA_INSTALLATION=ON
ARG BUILD_TYPE=Release
ARG EXTERNAL_GVA_BUILD_FLAGS

RUN mkdir -p dl-streamer/build \
    && cd dl-streamer/build \
    && cmake \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DVERSION_PATCH=${SOURCE_REV} \
        -DGIT_INFO=${GIT_INFO} \
        -DENABLE_PAHO_INSTALLATION=${ENABLE_PAHO_INSTALLATION} \
        -DENABLE_RDKAFKA_INSTALLATION=${ENABLE_RDKAFKA_INSTALLATION} \
        -DENABLE_VAAPI=ON \
        -DENABLE_VAS_TRACKER=ON \
        ${EXTERNAL_GVA_BUILD_FLAGS} \
        .. \
    && make -j $(nproc) \
    && make install \
    && ldconfig \
    && rm -rf ${OV_DLSTREAMER_DIR}/lib \
    && rm -rf ${OV_DLSTREAMER_DIR}/samples \
    && cp -r ../* ${OV_DLSTREAMER_DIR} \
    && ln --symbolic ${OV_DLSTREAMER_DIR}/build/intel64/Release/lib ${OV_DLSTREAMER_DIR}/lib \
    && rm -rf ../../dl-streamer

WORKDIR ${OV_DLSTREAMER_DIR}/samples

CMD ["/bin/bash"]
