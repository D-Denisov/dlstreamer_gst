# ==============================================================================
# Copyright (C) 2018-2021 Intel Corporation
#
# SPDX-License-Identifier: MIT
# ==============================================================================

ARG http_proxy
ARG https_proxy
ARG DOCKER_PRIVATE_REGISTRY

FROM ${DOCKER_PRIVATE_REGISTRY}ubuntu18_data_runtime:latest
LABEL Description="This is the base image for GSTREAMER & OpenVINO™ Toolkit Ubuntu 18.04 LTS"
LABEL Vendor="Intel Corporation"
WORKDIR /root
USER root

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
    && python3.6 -m pip install numpy==1.19.2 opencv-python==4.2.0.34 pytest==6.0.1 requests

# Install Intel MediaSDK
RUN wget https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-20.5.1/MediaStack.tar.gz && \
    tar -xvf MediaStack.tar.gz && \
    cp -r MediaStack/opt / && \
    cp -r MediaStack/etc / && \
    rm -rf MediaStack

# Install NEO OCL drivers
RUN mkdir neo && cd neo \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-gmmlib_20.2.4_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-igc-core_1.0.4756_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-igc-opencl_1.0.4756_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-opencl_20.35.17767_amd64.deb \
    && wget https://github.com/intel/compute-runtime/releases/download/20.35.17767/intel-ocloc_20.35.17767_amd64.deb \
    && dpkg -i intel*.deb

ARG LIBEXECDIR=bin/
ARG INCLUDEDIR=include/

ENV GSTREAMER_DIR=/opt/intel/openvino/data_processing/gstreamer
ENV GSTREAMER_LIB_DIR=${GSTREAMER_DIR}/lib
ENV ST_PLUGIN_SCANNER=${GSTREAMER_DIR}/bin/gstreamer-1.0/gst-plugin-scanner
ENV C_INCLUDE_PATH=${GSTREAMER_DIR}/${INCLUDEDIR}:${C_INCLUDE_PATH}
ENV CPLUS_INCLUDE_PATH=${GSTREAMER_DIR}/${INCLUDEDIR}:${CPLUS_INCLUDE_PATH}

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
ENV PATH=/usr/bin:${GSTREAMER_DIR}/${LIBEXECDIR}:/opt/intel/mediasdk/bin:${PATH}

ENV LIBVA_DRIVERS_PATH=/opt/intel/mediasdk/lib64
ENV LIBVA_DRIVER_NAME=iHD
ENV GST_VAAPI_ALL_DRIVERS=1
ENV DISPLAY=:0.0
ENV LD_LIBRARY_PATH=/usr/lib/gst-video-analytics:${LD_LIBRARY_PATH}
ENV HDDL_INSTALL_DIR=/opt/intel/openvino/inference_engine/external/hddl
ENV ngraph_DIR=/opt/intel/openvino/deployment_tools/ngraph/cmake/

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

RUN source /opt/intel/openvino/bin/setupvars.sh && \
    mkdir -p dl-streamer/build \
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
