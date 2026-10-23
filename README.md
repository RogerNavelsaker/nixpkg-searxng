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
- Entrypoint: `/bin/searxng-entrypoint`; it initializes settings and then execs Granian with `searx.webapp:app`.
- If `/etc/searxng/settings.yml` is absent, the entrypoint copies the pinned upstream settings template, replaces `ultrasecretkey` with a random 48-character hexadecimal key, then atomically installs it with mode `0600`. Existing settings files are left unchanged.
- `/etc/searxng` and `/var/cache/searxng` must exist as directories. When settings are generated, `/etc/searxng` must also be writable.
- Keep generated settings on a persistent volume to keep the same secret across container recreation. An ephemeral/removed anonymous volume loses the generated settings and causes a new key to be generated next start.
- `FORCE_OWNERSHIP` defaults to `true`: when started as UID 0, the entrypoint recursively changes config/data volume ownership to `10001:10001`. Otherwise it warns on ownership mismatch. Set `FORCE_OWNERSHIP=false` to disable that repair.
- `SEARXNG_PORT` overrides `GRANIAN_PORT` when it contains only digits; the default port is 8080 and the image exposes TCP 8080.
- CA certificates and timezone database are included. `/tmp` is mode 1777; provide a tmpfs mount for read-only-root operation.
- Granian, the SearXNG Python runtime, Dash, coreutils, and GNU sed are included; no package manager is included.

For local health validation, use only a disposable settings file with a throwaway key and a private test network. Do not include production config or credentials in build inputs.
