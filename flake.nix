{
  description = "SearXNG OCI image built with Nix dockerTools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      searxng = pkgs.searxng.overrideAttrs (old: {
        version = "0-unstable-2026-10-19";
        src = pkgs.fetchFromGitHub {
          owner = "searxng";
          repo = "searxng";
          rev = "81371861f67226091d1c4df2e3908a11d3b54eb9";
          hash = "sha256-d9KztINkg47H1Shr6lzJEN6B/zhUcZT0ec66BipJnnI=";
        };
      });
      image = pkgs.dockerTools.buildLayeredImage {
        name = "searxng";
        tag = searxng.version;
        contents = [ searxng pkgs.dockerTools.fakeNss pkgs.cacert pkgs.tzdata ];

        config = {
          User = "10001:10001";
          WorkingDir = "/var/cache/searxng";
          Entrypoint = [ "${searxng}/bin/searxng-run" ];
          Env = [
            "SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml"
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "TZDIR=${pkgs.tzdata}/share/zoneinfo"
          ];
          ExposedPorts = { "8080/tcp" = { }; };
          Volumes = {
            "/etc/searxng" = { };
            "/var/cache/searxng" = { };
          };
        };

        fakeRootCommands = ''
          mkdir -p ./etc/searxng ./tmp ./var/cache/searxng
          chown -R 10001:10001 ./var/cache/searxng
          chmod 0700 ./var/cache/searxng
          chmod 1777 ./tmp
        '';
      };
    in {
      packages.${system} = {
        inherit image;
        default = image;
      };
      checks.${system} = { inherit image; };
    };
}
