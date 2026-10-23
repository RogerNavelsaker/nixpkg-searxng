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
      # searxng-run starts Flask's development server; the container contract uses Granian.
      granian = pkgs.python3Packages.granian;
      searxngPythonPath = pkgs.python3Packages.makePythonPath [ searxng ];
      settingsTemplate = pkgs.runCommand "searxng-settings-template" { } ''
        mkdir -p "$out"
        cp ${searxng.src}/container/settings.template.yml "$out/settings.template.yml"
      '';
      entrypoint = pkgs.runCommand "searxng-entrypoint" { } ''
        mkdir -p "$out/bin"
        substitute ${./container/entrypoint.sh} "$out/bin/searxng-entrypoint" \
          --replace-fail @dash@ ${pkgs.dash} \
          --replace-fail @coreutils@ ${pkgs.coreutils} \
          --replace-fail @gnused@ ${pkgs.gnused} \
          --replace-fail @granian@ ${granian} \
          --replace-fail @searxng@ ${searxng} \
          --replace-fail @settingsTemplate@ ${settingsTemplate}
        chmod +x "$out/bin/searxng-entrypoint"
      '';
      entrypointTest = pkgs.runCommand "searxng-entrypoint-test" {
        nativeBuildInputs = [ pkgs.gnugrep ];
      } ''
        ${pkgs.bash}/bin/bash ${./tests/entrypoint.sh} ${entrypoint}/bin/searxng-entrypoint
        touch "$out"
      '';
      image = pkgs.dockerTools.buildLayeredImage {
        name = "searxng";
        tag = searxng.version;
        contents = [
          searxng
          granian
          entrypoint
          settingsTemplate
          pkgs.dockerTools.fakeNss
          pkgs.cacert
          pkgs.tzdata
          pkgs.dash
          pkgs.coreutils
          pkgs.gnused
        ];

        config = {
          User = "10001:10001";
          WorkingDir = "/var/cache/searxng";
          Entrypoint = [ "/bin/searxng-entrypoint" ];
          Env = [
            "__SEARXNG_VERSION=${searxng.version}"
            "__SEARXNG_CONFIG_PATH=/etc/searxng"
            "__SEARXNG_DATA_PATH=/var/cache/searxng"
            "__SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml"
            "SEARXNG_SETTINGS_PATH=/etc/searxng/settings.yml"
            "PYTHONPATH=${searxngPythonPath}"
            "GRANIAN_PROCESS_NAME=searxng"
            "GRANIAN_INTERFACE=wsgi"
            "GRANIAN_HOST=::"
            "GRANIAN_PORT=8080"
            "GRANIAN_WEBSOCKETS=false"
            "GRANIAN_BLOCKING_THREADS=4"
            "GRANIAN_WORKERS_KILL_TIMEOUT=30s"
            "GRANIAN_BLOCKING_THREADS_IDLE_TIMEOUT=5m"
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
          chown -R 10001:10001 ./etc/searxng ./var/cache/searxng
          chmod 0700 ./etc/searxng ./var/cache/searxng
          chmod 1777 ./tmp
        '';
      };
    in {
      packages.${system} = {
        inherit image;
        default = image;
      };
      checks.${system} = {
        inherit image;
        entrypoint = entrypointTest;
      };
    };
}
