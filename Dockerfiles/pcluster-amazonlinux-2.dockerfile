FROM public.ecr.aws/amazonlinux/amazonlinux:2

RUN yum update -y \
    && amazon-linux-extras install -y epel \
    && yum update -y \
    && yum install -y \
    autoconf \
    automake \
    bzip2 \
    cpio \
    curl \
    environment-modules \
    file \
    findutils \
    gcc \
    gcc-c++ \
    gcc-gfortran \
    gettext \
    git \
    iputils \
    jansson-devel \
    jq \
    libevent-devel \
    libffi-devel \
    libibverbs-core \
    libtool \
    glibc-locale-source \
    m4 \
    make \
    mercurial \
    mlocate \
    ncurses-devel \
    openssl-devel \
    patch \
    patchelf \
    pciutils \
    perl-devel\
    python3-devel \
    python3-pip \
    rsync \
    tar \
    unzip \
    wget \
    which \
    xz \
    zlib-devel \
    && localedef -i en_US -f UTF-8 en_US.UTF-8 \
    && yum clean all \
    && rm -rf /var/cache/yum/*

RUN python3 -m pip install --upgrade pip setuptools wheel \
 && python3 -m pip install gnureadline 'boto3<=1.20.35' 'botocore<=1.23.46' pyyaml pytz minio requests clingo \
 && rm -rf ~/.cache

COPY gpg.yaml /spack.yaml
RUN git clone https://github.com/spack/spack /spack \
 && (cd /spack && curl -Lfs https://github.com/spack/spack/pull/37405.patch | patch -p1) \
 && export SPACK_ROOT=/spack \
 && . /spack/share/spack/setup-env.sh \
 && spack -e . concretize \
 && spack -e . install --make \
 && spack -e . gc -y \
 && spack clean -a \
 && rm -rf /spack /spack.yaml /spack.lock /.spack-env /root/.spack

ARG PCLUSTER_VERSION="3.5.1" \
    LIBJWT_VERSION="1.12.0" \
    PMIX_VERSION="3.2.3" \
    SLURM_VERSION="22-05-8-1" \
    EFA_INSTALLER_VERSION="1.22.0"

# Install SLURM and libfabric as on ParalleCluster itself
RUN mkdir -p /opt/parallelcluster && echo "${PCLUSTER_VERSION}" > /opt/parallelcluster/.bootstrapped

RUN curl -sOL https://github.com/benmcollins/libjwt/archive/refs/tags/v${LIBJWT_VERSION}.tar.gz \
    && tar xf v${LIBJWT_VERSION}.tar.gz \
    && cd libjwt-${LIBJWT_VERSION}/ \
    && autoreconf --force --install \
    && ./configure --prefix=/opt/libjwt \
    && make -j \
    && make install && make clean \
    && cd .. \
    && rm -rf v${LIBJWT_VERSION}.tar.gz libjwt-${LIBJWT_VERSION}

RUN curl -sOL https://github.com/openpmix/openpmix/releases/download/v${PMIX_VERSION}/pmix-${PMIX_VERSION}.tar.gz \
    && tar xf pmix-${PMIX_VERSION}.tar.gz \
    && cd pmix-${PMIX_VERSION} \
    && ./autogen.pl \
    && ./configure --prefix=/opt/pmix \
    && make -j \
    && make install && make clean \
    && cd .. \
    && rm -rf pmix-${PMIX_VERSION}.tar.gz pmix-${PMIX_VERSION}

# Actual PCluster also configures `--enable-slurmrestd`
RUN curl -sOL https://github.com/SchedMD/slurm/archive/slurm-${SLURM_VERSION}.tar.gz \
    && tar xf slurm-${SLURM_VERSION}.tar.gz \
    && cd slurm-slurm-${SLURM_VERSION}/ \
    && ./configure --prefix=/opt/slurm --with-pmix=/opt/pmix --with-jwt=/opt/libjwt \
    && make -j \
    && make install && make install-contrib && make clean \
    && cd .. \
    && rm -rf slurm-${SLURM_VERSION}.tar.gz slurm-slurm-${SLURM_VERSION}

RUN curl -sOL https://efa-installer.amazonaws.com/aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && tar xf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz \
    && cd aws-efa-installer \
    && ./efa_installer.sh -y -k \
    && cd .. \
    && rm -rf aws-efa-installer-${EFA_INSTALLER_VERSION}.tar.gz aws-efa-installer

# Bootstrap spack compiler installation
RUN mkdir -p /bootstrap && \
    cd /bootstrap && \
    git clone https://github.com/spack/spack spack \
    && export SPACK_ROOT=/bootstrap/spack \
    && . spack/share/spack/setup-env.sh \
    && curl -sOL https://raw.githubusercontent.com/spack/spack-configs/main/AWS/parallelcluster/postinstall.sh \
    && /bin/bash postinstall.sh -fg -nointel \
    && spack clean -a \
    && cd /bootstrap/spack \
    && find . -type f -maxdepth 1 -delete \
    && rm -rf bin lib share var /root/.spack

ENV PATH=/bootstrap/runner/view/bin:$PATH \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    LANGUAGE=en_US:en \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

CMD ["/bin/bash"]
