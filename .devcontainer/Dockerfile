# hsfluidsynth development container
FROM debian:bookworm-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    curl \
    ca-certificates \
    git \
    openssh-client \
    gdb strace \
    ripgrep fd-find \
    vim tmux less \
    cmake \
    libglib2.0-dev \
    libsndfile1-dev \
    libgmp-dev \
    fluid-soundfont-gm \
    fluid-soundfont-gs \
    && rm -rf /var/lib/apt/lists/* \
    && test -f /usr/share/sounds/sf2/FluidR3_GM.sf2

# Build git from source (matches music-composer toolchain and supports jj >= 0.46).
ARG GIT_VERSION=2.54.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libexpat1-dev \
    libssl-dev \
    zlib1g-dev \
    && curl -fsSL --retry 5 --retry-all-errors --http1.1 -o /tmp/git.tar.gz \
       "https://github.com/git/git/archive/refs/tags/v${GIT_VERSION}.tar.gz" \
    && tar -C /tmp -xf /tmp/git.tar.gz \
    && make -C "/tmp/git-${GIT_VERSION}" -j"$(nproc)" prefix=/usr/local \
       NO_TCLTK=1 NO_GETTEXT=1 NO_PYTHON=1 all \
    && make -C "/tmp/git-${GIT_VERSION}" prefix=/usr/local \
       NO_TCLTK=1 NO_GETTEXT=1 NO_PYTHON=1 install \
    && rm -rf /tmp/git.tar.gz "/tmp/git-${GIT_VERSION}" /var/lib/apt/lists/* \
    && git --version

# Build FluidSynth 2.5.5 to /usr/local (matches music-composer cmake flags).
ARG FLUIDSYNTH_VERSION=2.5.5
RUN curl -fsSL --retry 5 --retry-all-errors --http1.1 -o /tmp/fs.tar.gz \
       "https://github.com/FluidSynth/fluidsynth/archive/refs/tags/v${FLUIDSYNTH_VERSION}.tar.gz" \
    && tar xzf /tmp/fs.tar.gz -C /tmp \
    && cmake -S "/tmp/fluidsynth-${FLUIDSYNTH_VERSION}" -B /tmp/fs-build \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_INSTALL_PREFIX=/usr/local \
         -Denable-pulseaudio=OFF \
         -Denable-jack=OFF \
         -Denable-pipewire=OFF \
         -Denable-sdl2=OFF \
         -Denable-dbus=OFF \
         -Denable-readline=OFF \
         -Denable-network=OFF \
    && cmake --build /tmp/fs-build --parallel "$(nproc)" \
    && cmake --install /tmp/fs-build \
    && mkdir -p /usr/local/share/soundfonts \
    && (cp -f "/tmp/fluidsynth-${FLUIDSYNTH_VERSION}"/sf2/*.sf* /usr/local/share/soundfonts/ 2>/dev/null || true) \
    && ldconfig \
    && pkg-config --modversion fluidsynth \
    && rm -rf /tmp/fs.tar.gz "/tmp/fluidsynth-${FLUIDSYNTH_VERSION}" /tmp/fs-build

# GHC + cabal via ghcup
RUN ARCH=$(uname -m) \
    && case "$ARCH" in aarch64) GHCUP_ARCH=aarch64 ;; *) GHCUP_ARCH=x86_64 ;; esac \
    && curl -fsSL --retry 5 --retry-all-errors --http1.1 "https://downloads.haskell.org/~ghcup/${GHCUP_ARCH}-linux-ghcup" -o /usr/local/bin/ghcup \
    && chmod +x /usr/local/bin/ghcup \
    && ghcup install ghc 9.10.3 --set \
    && ghcup install cabal 3.16.1.0 --set \
    && ghcup gc \
    && rm -rf /root/.ghcup/ghc/*/share/doc /root/.ghcup/cache /root/.ghcup/tmp

ENV PATH="/root/.local/bin:/root/.ghcup/bin:/root/.cabal/bin:${PATH}"
ENV LANG=C.UTF-8

# Install ormolu and hlint separately: hlint pins ghc-lib-parser 9.12, ormolu pins 9.14.
# Bound parallelism and skip -O1 on dev tools to avoid RAM thrashing in Docker VM.
RUN cabal update \
    && cabal install -j2 --disable-optimization ormolu-0.8.1.1 --installdir=/usr/local/bin --overwrite-policy=always \
    && cabal install -j2 --disable-optimization hlint-3.10 --installdir=/usr/local/bin --overwrite-policy=always \
    && rm -rf /root/.cache/cabal /root/.cabal/store /root/.cabal/logs /root/.cabal/packages

# jj
ARG JJ_VERSION=v0.46.0
RUN ARCH=$(uname -m) \
    && case "$ARCH" in aarch64) JJ_ARCH=aarch64 ;; x86_64) JJ_ARCH=x86_64 ;; esac \
    && curl -fsSL --retry 5 --retry-all-errors --http1.1 -o /tmp/jj.tar.gz \
       "https://github.com/jj-vcs/jj/releases/download/${JJ_VERSION}/jj-${JJ_VERSION}-${JJ_ARCH}-unknown-linux-musl.tar.gz" \
    && tar xzf /tmp/jj.tar.gz -C /usr/local/bin ./jj \
    && rm /tmp/jj.tar.gz

WORKDIR /workspace

CMD ["/bin/bash"]
