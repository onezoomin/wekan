FROM debian:buster-slim
MAINTAINER wekan

ENV PORT=80
EXPOSE $PORT

# Declare Arguments Set the environment variables only before they are needed
ENV BUILD_DEPS="apt-utils gnupg gosu wget curl bzip2 build-essential python git ca-certificates gcc-7 paxctl"
# including paxctl fix for alpine linux: https://github.com/wekan/wekan/issues/1303

RUN \
    # OS dependencies
    apt-get update -y && apt-get install -y --no-install-recommends ${BUILD_DEPS}

ARG ARCHITECTURE
ENV ARCHITECTURE ${ARCHITECTURE:-linux-x64}
ARG NODE_VERSION
ENV NODE_VERSION ${NODE_VERSION:-v8.9.3}

RUN \
    # Download nodejs
    wget https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${ARCHITECTURE}.tar.gz && \
    wget https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt.asc && \
    \
    # Verify nodejs authenticity
    grep ${NODE_VERSION}-${ARCHITECTURE}.tar.gz SHASUMS256.txt.asc | shasum -a 256 -c - && \
    export GNUPGHOME="$(mktemp -d)" && \

    # Try other key servers if ha.pool.sks-keyservers.net is unreachable
    # Code from https://github.com/chorrell/docker-node/commit/2b673e17547c34f17f24553db02beefbac98d23c
    # gpg keys listed at https://github.com/nodejs/node#release-team
    # and keys listed here from previous version of this Dockerfile
    for key in \
    9554F04D7259F04124DE6B476D5A82AC7E37093B \
    94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
    FD3A5288F042B6850C66B31F09FE44734EB7990E \
    71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
    DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
    C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
    B9AE9905FFD7803F25714661B63B535A4C206CA9 \
    ; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" || \
    gpg --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --keyserver keyserver.pgp.com --recv-keys "$key" ; \
    done && \
    gpg --verify SHASUMS256.txt.asc && \
    # Ignore socket files then delete files then delete directories
    find "$GNUPGHOME" -type f | xargs rm -f && \
    find "$GNUPGHOME" -type d | xargs rm -fR && \
    rm -f SHASUMS256.txt.asc

ARG NPM_VERSION
ENV NPM_VERSION ${NPM_VERSION:-5.5.1}
ARG FIBERS_VERSION
ENV FIBERS_VERSION ${FIBERS_VERSION:-2.0.0}
RUN \
    # Install Node
    tar xvzf node-${NODE_VERSION}-${ARCHITECTURE}.tar.gz && \
    rm node-${NODE_VERSION}-${ARCHITECTURE}.tar.gz && \
    mv node-${NODE_VERSION}-${ARCHITECTURE} /opt/nodejs && \
    ln -s /opt/nodejs/bin/node /usr/bin/node && \
    ln -s /opt/nodejs/bin/npm /usr/bin/npm && \
    # paxctl fix for alpine linux: https://github.com/wekan/wekan/issues/1303
    paxctl -mC `which node` && \
    # Install Node dependencies
    npm install -g npm@${NPM_VERSION} && \
    npm install -g node-gyp && \
    npm install -g fibers@${FIBERS_VERSION}

ARG METEOR_RELEASE
ENV METEOR_RELEASE ${METEOR_RELEASE:-1.6.0.1}
ARG METEOR_EDGE
ENV METEOR_EDGE ${METEOR_EDGE:-1.5-beta.17}
ARG USE_EDGE
ENV USE_EDGE ${USE_EDGE:-false}
RUN \
    # Add non-root user wekan
    mkdir /home/wekan  && useradd --user-group --system --home-dir /home/wekan wekan && \
    # Change user to wekan and install meteor
    cd /home/wekan/ && \
    chown wekan:wekan --recursive /home/wekan && \
    curl https://install.meteor.com -o /home/wekan/install_meteor.sh && \
    sed -i "s|RELEASE=.*|RELEASE=${METEOR_RELEASE}\"\"|g" ./install_meteor.sh && \
    echo "Starting meteor ${METEOR_RELEASE} installation...   \n" && \
    chown wekan:wekan /home/wekan/install_meteor.sh && \
    \
    # Check if opting for a release candidate instead of major release
    if [ "$USE_EDGE" = false ]; then \
      gosu wekan:wekan sh /home/wekan/install_meteor.sh; \
    else \
      gosu wekan:wekan git clone --recursive --depth 1 -b release/METEOR@${METEOR_EDGE} git://github.com/meteor/meteor.git /home/wekan/.meteor; \
    fi;

# Copy the app to the image
ARG SRC_PATH
ENV SRC_PATH ${SRC_PATH:-./}
COPY ${SRC_PATH} /home/wekan/app

RUN \
    # Get additional packages
    mkdir -p /home/wekan/app/packages && \
    chown wekan:wekan --recursive /home/wekan && \
    cd /home/wekan/app/packages && \
    gosu wekan:wekan git clone --depth 1 -b master git://github.com/wekan/flow-router.git kadira-flow-router && \
    gosu wekan:wekan git clone --depth 1 -b master git://github.com/meteor-useraccounts/core.git meteor-useraccounts-core && \
    sed -i 's/api\.versionsFrom/\/\/api.versionsFrom/' /home/wekan/app/packages/meteor-useraccounts-core/package.js && \
    cd /home/wekan/.meteor && \
    gosu wekan:wekan /home/wekan/.meteor/meteor -- help;

RUN \
    # Build app
    echo "Building app" && cd /home/wekan/app && \
    gosu wekan:wekan /home/wekan/.meteor/meteor add standard-minifier-js && \
    gosu wekan:wekan /home/wekan/.meteor/meteor npm install && \
    gosu wekan:wekan /home/wekan/.meteor/meteor build --directory /home/wekan/app_build && \
    cp /home/wekan/app/fix-download-unicode/cfs_access-point.txt /home/wekan/app_build/bundle/programs/server/packages/cfs_access-point.js && \
    chown wekan:wekan /home/wekan/app_build/bundle/programs/server/packages/cfs_access-point.js

RUN \
    echo "node_modules bcrypt" && \
    cd /home/wekan/app_build/bundle/programs/server/npm/node_modules/meteor/npm-bcrypt && \
    gosu wekan:wekan rm -rf node_modules/bcrypt && \
    gosu wekan:wekan npm install bcrypt

RUN \
    echo "server bcrypt" && \
    cd /home/wekan/app_build/bundle/programs/server/ && \
    gosu wekan:wekan npm install && \
    gosu wekan:wekan npm install bcrypt && \
    mv /home/wekan/app_build/bundle /build && \
    \
    # Cleanup
    apt-get remove --purge -y ${BUILD_DEPS} && \
    apt-get autoremove -y && \
    rm -R /var/lib/apt/lists/* && \
    rm -R /home/wekan/.meteor && \
    rm -R /home/wekan/app && \
    rm -R /home/wekan/app_build && \
    rm /home/wekan/install_meteor.sh

CMD ["node", "/build/main.js"]
