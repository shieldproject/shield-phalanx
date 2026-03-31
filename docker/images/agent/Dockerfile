ARG UBUNTU_RELEASE=noble
ARG GO_VERSION=1.26.1

FROM ubuntu:${UBUNTU_RELEASE} AS build
ARG GO_VERSION
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y bzip2 gzip unzip curl git make gcc libc6-dev openssh-client ca-certificates \
 && curl -sL https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz | tar -C /usr/local -xzf - \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/go/bin:/go/bin:${PATH}" \
    GOPATH="/go"

# Build SHIELD from source (cloned into src/shield/ by Makefile)
COPY src/shield/ /go/src/github.com/shieldproject/shield/
RUN cd /go/src/github.com/shieldproject/shield \
 && go mod tidy \
 && go mod vendor \
 && make build BUILD_TYPE="build -ldflags='-X main.Version=phalanx-dev'"

RUN mkdir -p /dist/bin /dist/plugins \
 && mv /go/src/github.com/shieldproject/shield/shield-agent \
       /go/src/github.com/shieldproject/shield/shield-crypt \
       /go/src/github.com/shieldproject/shield/shield-report \
       /go/src/github.com/shieldproject/shield/bin/shield-pipe \
       /dist/bin/ \
 && for plugin in $(cat /go/src/github.com/shieldproject/shield/plugins); do \
      cp /go/src/github.com/shieldproject/shield/$plugin /dist/plugins/; \
    done

FROM ubuntu:${UBUNTU_RELEASE}
ARG UBUNTU_RELEASE
ARG TARGETARCH

# Add PostgreSQL apt repository (needed for postgresql-client-16)
RUN apt-get update \
 && apt-get install -y curl gnupg \
 && sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt ${UBUNTU_RELEASE}-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Install database client tools for SHIELD plugins
RUN apt-get update \
 && apt-get install -y \
      bzip2 \
      netcat-openbsd \
      openssh-server \
      openssh-client \
      postgresql-client-16 \
      mariadb-client \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Add MongoDB tools repository and install (7.0 for jammy, 8.0 for noble+)
RUN case "${UBUNTU_RELEASE}" in \
      jammy) MONGO_VER=7.0 ;; \
      *)     MONGO_VER=8.0 ;; \
    esac \
 && curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGO_VER}.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server.gpg \
 && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_RELEASE}/mongodb-org/${MONGO_VER} multiverse" > /etc/apt/sources.list.d/mongodb-org.list \
 && apt-get update \
 && apt-get install -y mongodb-database-tools mongodb-mongosh \
 && rm -rf /var/lib/apt/lists/*

# Install etcdctl
ARG ETCD_VERSION=3.6.9
RUN curl -sL https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz \
  | tar xzf - --strip-components=1 -C /usr/local/bin etcd-v${ETCD_VERSION}-linux-${TARGETARCH}/etcdctl

# Install consul CLI
ARG CONSUL_VERSION=1.22.6
RUN curl -sLo /tmp/consul.zip https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${TARGETARCH}.zip \
 && unzip /tmp/consul.zip -d /usr/local/bin/ \
 && rm /tmp/consul.zip

# Create vcap user
RUN useradd -r -m -s /bin/bash vcap

# Copy SHIELD agent and plugins
COPY --from=build /dist/bin/ /shield/bin/
COPY --from=build /dist/plugins/ /shield/plugins/

# Copy config and entrypoint
COPY docker/images/agent/agent.conf /shield/config/agent.conf
COPY docker/images/agent/entrypoint.sh /shield/init/agent

RUN chmod 0755 /shield/init/agent \
 && mkdir -p /shield/store /etc/shield \
 && chown -R vcap:vcap /shield/store

ENV PATH="/shield/bin:/shield/plugins:${PATH}"

EXPOSE 5444

ENTRYPOINT ["/shield/init/agent"]
