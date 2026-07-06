# meshvpn — container image. Tiny: bash + the scripts. No WireGuard runtime is
# needed (meshvpn generates config text; it does not bring interfaces up).
FROM alpine:3.20
LABEL org.opencontainers.image.title="meshvpn" \
      org.opencontainers.image.description="WireGuard-style overlay deploy helper: validate, generate (placeholder keys), graph, healthcheck" \
      org.opencontainers.image.source="https://github.com/cognis-digital/meshvpn" \
      org.opencontainers.image.licenses="LicenseRef-COCL-1.0"

RUN apk add --no-cache bash
WORKDIR /work
COPY meshvpn.sh /opt/meshvpn/meshvpn.sh
COPY lib/ /opt/meshvpn/lib/
COPY examples/ /opt/meshvpn/examples/
RUN chmod +x /opt/meshvpn/meshvpn.sh && ln -s /opt/meshvpn/meshvpn.sh /usr/local/bin/meshvpn

# Mount your fleet config into /work and pass paths relative to it.
ENTRYPOINT ["meshvpn"]
CMD ["--help"]
