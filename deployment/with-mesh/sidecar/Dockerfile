FROM envoyproxy/envoy:v1.28-latest

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget unzip net-tools && \
    rm -rf /var/lib/apt/lists/*

ARG CONSUL_VERSION=1.18.2
RUN wget -q -O /tmp/consul.zip \
    "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip" && \
    unzip -d /usr/local/bin /tmp/consul.zip && \
    rm /tmp/consul.zip && \
    chmod +x /usr/local/bin/consul

RUN consul version && envoy --version

ENTRYPOINT []
CMD ["/bin/sh"]