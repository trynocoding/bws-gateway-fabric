# BWS data plane image

The BWS data plane image is built from the vendor distribution and BWS Agent. The M4 image uses BWS-owned runtime
paths while retaining the Agent/control-plane wire protocol used by the M3 compatibility baseline.

## Build

Keep the `bws-agent` repository and BWS archive next to this repository, then run:

```shell
make build-bws-image \
  BWS_AGENT_DIR=../bws-agent \
  BWS_PACKAGE=../bws-3.2.0-LINUX-X64.tar_94b299d8d6b5c686ffbe0ee912c79cbb304b93dc.gz \
  BWS_PREFIX=bws-gateway-fabric/bws \
  TAG=m2-local
```

The build compiles the `bws-agent` executable with `CGO_ENABLED=0`, validates the archive against the recorded SHA-256, and uses Rocky
Linux 8 as the glibc runtime. The BWS archive is supplied as a read-only named build context and is not copied into this
repository or retained in an image layer. The packaged dynamic-module dependencies, NGF NJS files, and NGF bootstrap
configuration are included in the image.

Development builds additionally install troubleshooting tools by default: `ps`/`top` (`procps-ng`), `ss`/`ip`
(`iproute`), `dig`/`nslookup`, `ping`, `lsof`, `netstat`, `less`, and `vi`. Disable those optional packages for a
production-oriented image:

```shell
make build-bws-image BWS_INSTALL_DEBUG_TOOLS=false
```

The image label `org.bws.image.debug-tools` records whether the optional packages were included. Rocky Linux retains
`curl` in both image variants. Some commands such as `ping` may still be limited by the Pod security context because
the NGF data plane drops all Linux capabilities.

The vendor `bws.sh` environment initialization is retained. Its final command is changed from `./bws "$@"` to
`exec ./bws "$@"` so the entrypoint can track and signal the BWS master process directly.

## License mount

The vendor license is deleted while the image is built. Supply it as a read-only Secret at:

```text
/var/run/secrets/bws/bws.lic.txt
```

BWS derives a writable `bws.lic` file from `bws.lic.txt`. The entrypoint therefore copies the read-only Secret into
`/var/cache/bws/license`, and `/opt/bws/license` points to that runtime directory. The `/var/cache/bws` `emptyDir`
keeps the derived license writable while the root filesystem and Secret mount remain read-only.

M3 must add the Secret volume and container mount through the existing `BwsProxy` pod/volume settings. The license
must not be mounted directly over `/opt/bws/license`.

## Runtime

The image runs as UID `101`, GID `1001`. The entrypoint starts BWS with:

```shell
/opt/bws/bin/bws.sh \
  -p /opt/bws \
  -c /etc/bws/nginx.conf \
  -g "daemon off;"
```

It waits for `/var/run/bws/bws.pid`, starts BWS Agent, and forwards `SIGTERM`, `SIGQUIT`, and `SIGINT` to both
processes. Set `BWS_AGENT_DISABLED=true` only for image-level smoke tests that intentionally run without a control plane.

The bootstrap configuration exposes `GET /readyz` on port `8081`. NGF replaces the generated configuration after the
Agent connects.

## Local smoke test

The following mirrors the NGF non-root and read-only-root-filesystem settings:

```shell
docker run --rm --read-only \
  --tmpfs /var/cache/bws:rw,uid=101,gid=1001,mode=0770 \
  --tmpfs /var/run/bws:rw,uid=101,gid=1001,mode=0770 \
  --tmpfs /tmp:rw,uid=101,gid=1001,mode=0770 \
  -e BWS_AGENT_DISABLED=true \
  -v "$PWD/bws.lic.txt:/var/run/secrets/bws/bws.lic.txt:ro" \
  -p 18081:8081 \
  bws-gateway-fabric/bws:m2-local
```

The M2 local verification covered archive and license exclusion checks, all packaged dynamic module dependencies,
`BES WebServer 3.2.0.242`, `bws -t`, readiness, SIGHUP worker replacement, and clean SIGTERM exit. Kubernetes Secret
wiring, Agent/control-plane connection, generated route configuration, and ports 80/443 are M3 E2E work.
