FROM alpine:latest

# export MUSL_LOCALE_DEPS="cmake make musl-dev gcc gettext-dev libintl" && \
# export MUSL_LOCPATH="/usr/share/i18n/locales/musl" && \
# apk update && \
# apk upgrade && \
# apk add --no-cache $MUSL_LOCALE_DEPS ca-certificates git python3 sudo tzdata bash && \
# apk add --no-cache nodejs npm
# ln -sf /usr/bin/node /usr/local/bin/node
# ln -sf /usr/bin/npm /usr/local/bin/npm
# ln -sf /usr/bin/npx /usr/local/bin/npx
# wget https://gitlab.com/rilian-la-te/musl-locales/-/archive/master/musl-locales-master.zip && \
# unzip musl-locales-master.zip && \
# cd musl-locales-master && \
# cmake -DLOCALE_PROFILE=OFF -D CMAKE_INSTALL_PREFIX:PATH=/usr . && \
# make && make install && \
# cd .. && rm -r musl-locales-master musl-locales-master.zip && \
# export LANG="C.UTF-8" && \
# adduser -D -h /home/zulip -u 1000 zulip && \
# echo 'zulip ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
# apk add --no-cache shellcheck
# apk add --no-cache shfmt
# apk add --no-cache py3-pip
# pip install transifex-client

ENV MUSL_LOCALE_DEPS cmake make musl-dev gcc gettext-dev libintl
ENV MUSL_LOCPATH /usr/share/i18n/locales/musl
RUN apk add --no-cache \
    $MUSL_LOCALE_DEPS \
    && wget https://gitlab.com/rilian-la-te/musl-locales/-/archive/master/musl-locales-master.zip \
    && unzip musl-locales-master.zip \
      && cd musl-locales-master \
      && cmake -DLOCALE_PROFILE=OFF -D CMAKE_INSTALL_PREFIX:PATH=/usr . && make && make install \
      && cd .. && rm -r musl-locales-master
    #   export MUSL_LOCALE_DEPS="cmake make musl-dev gcc gettext-dev libintl"
    #   export MUSL_LOCPATH="/usr/share/i18n/locales/musl"
      
    #   apk add --no-cache $MUSL_LOCALE_DEPS && \
    #       wget https://gitlab.com/rilian-la-te/musl-locales/-/archive/master/musl-locales-master.zip && \
    #       unzip musl-locales-master.zip && \
    #       cd musl-locales-master && \
    #       cmake -DLOCALE_PROFILE=OFF -D CMAKE_INSTALL_PREFIX:PATH=/usr . && make && make install && \
    #       cd .. && rm -r musl-locales-master

ENV LANG="C.UTF-8"
    # export LANG="C.UTF-8"

RUN apk update && \
    apk upgrade && \
    apk add --no-cache ca-certificates git python3 sudo tzdata bash

RUN adduser -D -h /home/zulip -u 1000 zulip
RUN echo 'zulip ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER zulip
WORKDIR /home/zulip
# ARG ZULIP_GIT_URL=https://github.com/zulip/zulip.git
# ARG ZULIP_GIT_REF=9.3

# RUN git clone "$ZULIP_GIT_URL" && \
#     cd zulip && \
#     git checkout -b current "$ZULIP_GIT_REF"

RUN exit     
RUN chown -R zulip:zulip /home/zulip/zulip
RUN chmod -R u+rwx /home/zulip/zulip

USER zulip
WORKDIR /home/zulip/zulip

ARG CUSTOM_CA_CERTIFICATES

# RUN SKIP_VENV_SHELL_WARNING=1 ./tools/provision --build-release-tarball-only












# This is a 2-stage Docker build.  In the first stage, we build a
# Zulip development environment image and use
# tools/build-release-tarball to generate a production release tarball
# from the provided Git ref
FROM alpine:latest AS base

# Set up working locales and upgrade the base image
ENV LANG="C.UTF-8"

ARG ALPINE_MIRROR

RUN { [ ! "$ALPINE_MIRROR" ] || sed -i "s|http://dl-cdn.alpinelinux.org/alpine/|$ALPINE_MIRROR |" /etc/apk/repositories; } && \
    apk update && \
    apk upgrade && \
    apk add --no-cache ca-certificates git python3 sudo tzdata bash py3-pip curl jq nano && \ 
    adduser -D -h /home/zulip -u 1000 zulip

FROM base AS build

RUN echo 'zulip ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

USER zulip
WORKDIR /home/zulip

# You can specify these in docker-compose.yml or with
#   docker build --build-arg "ZULIP_GIT_REF=git_branch_name" .
ARG ZULIP_GIT_URL=https://github.com/zulip/zulip.git
ARG ZULIP_GIT_REF=9.3

RUN git clone "$ZULIP_GIT_URL" && \
    cd zulip && \
    git checkout -b current "$ZULIP_GIT_REF"

WORKDIR /home/zulip/zulip

ARG CUSTOM_CA_CERTIFICATES

# Finally, we provision the development environment and build a release tarball
RUN SKIP_VENV_SHELL_WARNING=1 ./tools/provision --build-release-tarball-only && \
    . /srv/zulip-py3-venv/bin/activate && \
    ./tools/build-release-tarball docker && \
    mv /tmp/tmp.*/zulip-server-docker.tar.gz /tmp/zulip-server-docker.tar.gz

# In the second stage, we build the production image from the release tarball
FROM base

ENV DATA_DIR="/data"

# Then, with a second image, we install the production release tarball.
COPY --from=build /tmp/zulip-server-docker.tar.gz /root/
COPY custom_zulip_files/ /root/custom_zulip

ARG CUSTOM_CA_CERTIFICATES

RUN \
    # Make sure Nginx is not started by default.
    rc-update del nginx default && \
    mkdir -p "$DATA_DIR" && \
    cd /root && \
    tar -xf zulip-server-docker.tar.gz && \
    rm -f zulip-server-docker.tar.gz && \
    mv zulip-server-docker zulip && \
    cp -rf /root/custom_zulip/* /root/zulip && \
    rm -rf /root/custom_zulip && \
    /root/zulip/scripts/setup/install --hostname="$(hostname)" --email="docker-zulip" \
    --puppet-classes="zulip::profile::docker" --postgresql-version=14 && \
    rm -f /etc/zulip/zulip-secrets.conf /etc/zulip/settings.py && \
    apk del --purge && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

COPY entrypoint.sh /sbin/entrypoint.sh
COPY certbot-deploy-hook /sbin/certbot-deploy-hook

VOLUME ["$DATA_DIR"]
EXPOSE 80 443

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["app:run"]


  
