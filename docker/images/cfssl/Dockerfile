ARG UBUNTU_RELEASE=noble
FROM ubuntu:${UBUNTU_RELEASE}

ARG CFSSL_VERSION=1.6.5
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y curl openssl \
 && curl -sLo /usr/local/bin/cfssl https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_linux_${TARGETARCH} \
 && curl -sLo /usr/local/bin/cfssljson https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_linux_${TARGETARCH} \
 && chmod 0755 /usr/local/bin/cfssl /usr/local/bin/cfssljson \
 && rm -rf /var/lib/apt/lists/*

COPY docker/images/cfssl/generate-certs.sh /generate-certs.sh
RUN chmod 0755 /generate-certs.sh

ENTRYPOINT ["/generate-certs.sh"]
