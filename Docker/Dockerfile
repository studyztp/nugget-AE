# Start from the gem5 deps image
FROM ghcr.io/gem5/ubuntu-24.04_all-dependencies:latest

# Build-time args to match host user
ARG USERNAME=dev
ARG UID=1000
ARG GID=1000

# Create a group/user with the same UID/GID as on the host
RUN groupadd -g ${GID} ${USERNAME} \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}

# Create the work directory and set ownership
RUN mkdir -p /workdir \
    && chown ${UID}:${GID} /workdir

# Update and install libs (including HDF5, BLAS/LAPACK, MPI, OpenMP)
RUN apt-get update && apt-get install -y \
    libncurses-dev \
    libreadline-dev \
    python3-venv \
    python3-pybind11 \
    pybind11-dev \
    gdb \
    libhdf5-dev \
    libopenblas-dev \
    liblapack-dev \
    openmpi-bin \
    libopenmpi-dev \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*

# Python venv + deps
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -U pip setuptools wheel \
    && /opt/venv/bin/pip install --no-cache-dir pandas scikit-learn pybind11

ENV PATH="/opt/venv/bin:${PATH}"

# Set working directory (this is where you'll mount your host dir)
WORKDIR /workdir

# Switch to the non-root user
USER ${USERNAME}

# Default shell
CMD ["/bin/bash"]
