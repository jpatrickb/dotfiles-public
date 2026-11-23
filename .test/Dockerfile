# Fresh Ubuntu 26.04 with only what a stock install (plus WSL-ish setup) has:
# a sudo-capable non-root user, curl and git. chezmoi does the rest.
FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo curl ca-certificates git locales \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8
RUN useradd -m -s /bin/bash -G sudo tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
ENV HOME=/home/tester LANG=en_US.UTF-8
WORKDIR /home/tester
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /home/tester/.local/bin
