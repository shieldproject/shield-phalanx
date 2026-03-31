ARG UBUNTU_RELEASE=noble
ARG GO_VERSION=1.26.1

FROM ubuntu:${UBUNTU_RELEASE} AS go-base
ARG GO_VERSION
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y bzip2 gzip unzip curl git make gcc libc6-dev ca-certificates \
 && curl -sL https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz | tar -C /usr/local -xzf - \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/go/bin:/go/bin:${PATH}" \
    GOPATH="/go"

# Build SHIELD CLI from source (cloned into src/shield/ by Makefile)
FROM go-base AS build
COPY src/shield/ /go/src/github.com/shieldproject/shield/
RUN cd /go/src/github.com/shieldproject/shield \
 && go mod tidy \
 && go mod vendor \
 && go build -o /dist/shield ./cmd/shield

# Build s3util from source (pure Go, no CGO)
FROM go-base AS s3util-build
COPY docker/s3util/ /go/src/s3util/
RUN cd /go/src/s3util && CGO_ENABLED=0 go mod tidy && go build -o /dist/s3util .

FROM ubuntu:${UBUNTU_RELEASE}
ARG UBUNTU_RELEASE
ARG TARGETARCH

# Add PostgreSQL apt repository (gnupg + curl needed for key import)
RUN apt-get update \
 && apt-get install -y curl gnupg \
 && sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt ${UBUNTU_RELEASE}-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Install base tools
RUN apt-get update \
 && apt-get install -y \
      curl \
      file \
      jq \
      netcat-openbsd \
      openssl \
      diffutils \
      coreutils \
      postgresql-client-16 \
      mariadb-client \
      unzip \
 && rm -rf /var/lib/apt/lists/*

# Add MongoDB shell (7.0 for jammy, 8.0 for noble+)
RUN case "${UBUNTU_RELEASE}" in \
      jammy) MONGO_VER=7.0 ;; \
      *)     MONGO_VER=8.0 ;; \
    esac \
 && curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGO_VER}.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server.gpg \
 && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_RELEASE}/mongodb-org/${MONGO_VER} multiverse" > /etc/apt/sources.list.d/mongodb-org.list \
 && apt-get update \
 && apt-get install -y mongodb-mongosh \
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

# Install spruce
RUN curl -sLo /usr/local/bin/spruce https://github.com/geofffranks/spruce/releases/download/v1.31.1/spruce-linux-${TARGETARCH} \
 && chmod 0755 /usr/local/bin/spruce

# Copy SHIELD CLI from build stage
COPY --from=build /dist/shield /usr/local/bin/shield
COPY --from=s3util-build /dist/s3util /usr/local/bin/s3util
RUN chmod 0755 /usr/local/bin/shield /usr/local/bin/s3util

# Copy test scripts and data
COPY docker/images/tests/run.sh /tests/run.sh
COPY docker/images/tests/lib/functions.sh /tests/lib/functions.sh
COPY docker/images/tests/tests/ /tests/tests/
COPY docker/images/tests/data/ /tests/data/

RUN chmod 0755 /tests/run.sh /tests/lib/functions.sh /tests/tests/*.sh

WORKDIR /tests
ENTRYPOINT ["/tests/run.sh"]
