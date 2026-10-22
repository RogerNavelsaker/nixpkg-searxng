# SearXNG OCI image

Nix-built SearXNG image for x86_64 Linux using the pinned Nixpkgs package and `dockerTools`; no upstream OCI image is wrapped.

## Build

```sh
nix flake check
nix build .#image
podman load -i result
```

The lockfile pins Nixpkgs. SearXNG source is pinned separately to upstream commit `81371861f67226091d1c4df2e3908a11d3b54eb9` (2026-10-19), with a fixed source hash.

## Runtime contract

- Numeric non-root identity: `10001:10001`.
- Entrypoint: Nixpkgs `searxng-run`; TCP port metadata: 8080.
- Mount a SearXNG settings file at `/etc/searxng/settings.yml`. It must define a per-deployment secret key and bind address; no secret or generated config is included in the image.
- Writable cache path: `/var/cache/searxng` (optional cache data). `/tmp` is mode 1777; provide a tmpfs mount for read-only-root operation.
- CA certificates and timezone database are included.
- No shell or package manager is intentionally included.

For local health validation, use only a disposable settings file with a throwaway key and a private test network. Do not include production config or credentials in build inputs.
