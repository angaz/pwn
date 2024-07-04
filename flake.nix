{
  description = "Ethereum network crawler, API, and frontend";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{
    self,
    nixpkgs,
    devshell,
    flake-parts,
    gitignore,
    ...
  }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        devshell.flakeModule
        flake-parts.flakeModules.easyOverlay
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem = { config, pkgs, system, ... }: let
        inherit (gitignore.lib) gitignoreSource;
      in {
        # Attrs for easyOverlay
        overlayAttrs = {
          inherit (config.packages)
            pwnAPI;
        };

        packages = {
          nodeCrawler = pkgs.buildGo122Module {
            pname = "pwn-api";
            version = "0.0.0";

            src = gitignoreSource ./.;
            subPackages = [ "cmd/api" ];

            vendorHash = "";

            doCheck = false;

            CGO_ENABLED = 0;

            ldflags = [
              "-s"
              "-w"
              "-extldflags -static"
            ];
          };
        };

        devshells.default = {
          commands = [
            {
              name = "go-mod-vendor-hash";
              help = "Gets the vendor hash for the go modules";
              command = ''
                nix-prefetch --option extra-experimental-features flakes --silent \
                  '{ sha256 }: (builtins.getFlake (toString ./.)).packages.x86_64-linux.pwnAPI.goModules.overrideAttrs (_: { vendorSha256 = sha256; })'
              '';
            }
            {
              name = "go-mod-upgrade";
              help = "Upgrades the go dependencies. Prints the new vendorHash.";
              command = ''
                go get -u ./... && \
                go mod tidy && \
                go-mod-vendor-hash
              '';
            }
          ];

          packages = with pkgs; [
            go_1_22
            golangci-lint
            nix-prefetch
            nodejs
            postgresql_16
          ];
        };
      };

      flake = rec {
        nixosModules.default = nixosModules.pwn;
        nixosModules.pwn = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.pwn;
          apiAddress = cfg.api.address;
        in
        {
          options.services.pwn = {
            enable = mkEnableOption (self.flake.description);

            hostName = mkOption {
              type = types.str;
              default = "localhost";
              description = "Hostname to serve the PWN website on.";
            };

            nginx = mkOption {
              type = types.attrs;
              default = { };
              example = literalExpression ''
                {
                  forceSSL = true;
                  enableACME = true;
                }
              '';
              description = "Extra configuration for the vhost. Useful for adding SSL settings.";
            };

            stateDir = mkOption {
              type = types.path;
              default = /var/lib/pwn_api;
              description = "Directory where the databases will exist.";
            };

            snapshotDirname = mkOption {
              type = types.str;
              default = "/var/lib/postgres_backups/pwn_api";
              description = "Snapshots directory name.";
            };

            user = mkOption {
              type = types.str;
              default = "pwnapi";
              description = "User account under which the PWN API runs.";
            };

            group = mkOption {
              type = types.str;
              default = "pwnapi";
              description = "Group account under which the PWN API runs.";
            };

            dynamicUser = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Runs the PWN API as a SystemD DynamicUser.
                It means SystenD will allocate the user at runtime, and enables
                some other security features.
                If you are not sure what this means, it's safe to leave it default.
              '';
            };

            dailyBackup = mkOption {
              type = types.bool;
              default = true;
              description = ''
                Takes a daily backup of the Postgres database, saving it to the `snapshotDirname`.
              '';
            };

            dailyBackupRetention = mkOption {
              type = types.int;
              default = 7;
              description = "Number of days to keep backups for.";
            };

            api = {
              enable = mkOption {
                default = true;
                type = types.bool;
                description = "Enables the PWN API server.";
              };

              address = mkOption {
                type = types.str;
                default = "127.0.0.1:10000";
                description = "Listen address for the API server.";
              };

              metricsAddress = mkOption {
                type = types.str;
                default = "0.0.0.0:9190";
                description = "Address on which the metrics server listens. This is NOT added to the firewall.";
              };

              maxPoolConns = mkOption {
                type = types.int;
                default = 16;
                description = "Max number of open connections to the database.";
              };
            };

            postgresql = {
              enable = mkOption {
                default = true;
                type = types.bool;
                description = "Enables the Postgres database.";
              };
            };
          };

          config = mkIf cfg.enable {
            systemd.services = {
              pwn-api = mkIf cfg.api.enable {
                description = "PWN API server.";
                wantedBy = [ "multi-user.target" ];
                requires = [ "postgresql.service" ];
                after = [ "network.target" ]
                  ++ optional cfg.pwnAPI.enable "pwn-api.service";

                serviceConfig = {
                  ExecStart =
                  let
                    args = [
                      "--api-addr=${apiAddress}"
                      "--metrics-addr=${cfg.api.metricsAddress}"
                      "--postgres=\"host=/var/run/postgresql user=pwn database=pwn pool_max_conns=${toString cfg.api.maxPoolConns}\""
                    ];
                  in
                  "${pkgs.pwnAPI}/bin/pwn-api api ${concatStringsSep " " args}";

                  WorkingDirectory = cfg.stateDir;
                  StateDirectory = optional (cfg.stateDir == /var/lib/pwn_api) "pwn_api";

                  DynamicUser = cfg.dynamicUser;
                  Group = cfg.group;
                  User = cfg.user;

                  Restart = "on-failure";
                };
              };

              pwn-daily-backup = mkIf cfg.dailyBackup {
                enable = true;
                description = ''Daily Postgres backup for the PWN API.'';
                requires = [ "postgresql.service" ];
                startAt = "*-*-* 00:00:00";

                serviceConfig = {
                  Type = "oneshot";
                  Group = "postgres";
                  User = "postgres";
                  StateDirectory = "postgres_backups";
                };

                path = [
                  pkgs.coreutils
                  config.services.postgresql.package
                ];

                script = ''
                  set -e -o pipefail

                  mkdir -p "${cfg.snapshotDirname}"

                  dump_name="${cfg.snapshotDirname}/pwn_api_$(date --utc +%Y%m%dT%H%M%S).pgdump"

                  pg_dump \
                    --format custom \
                    --file "''${dump_name}.part" \
                    --host /var/run/postgresql \
                    pwn

                  mv "''${dump_name}.part" "''${dump_name}"

                  find "${cfg.snapshotDirname}" -ctime +${toString cfg.dailyBackupRetention} -name '*.pgdump' -delete
                '';
              };
            };

            services = {
              nginx = {
                enable = true;
                upstreams.pwnAPI.servers."${apiAddress}" = { };
                virtualHosts."${cfg.hostName}" = mkMerge [
                  cfg.nginx
                  {
                    locations = {
                      "/api" = {
                        proxyPass = "http://pwnAPI/";
                      };
                    };
                  }
                ];
              };
              postgresql = mkIf cfg.postgresql.enable {
                enable = true;
                enableJIT = true;
                package = pkgs.postgresql_16;
                settings = {
                  max_connections = (cfg.maxPoolConns) * 1.15;
                  shared_preload_libraries = concatStringsSep "," [
                    "pg_stat_statements"
                  ];

                  # Performance tuning.
                  effective_io_concurrency = 200;
                };
                ensureDatabases = [ "pwn" ];
                ensureUsers = [
                  {
                    name = "pwn";
                    ensureDBOwnership = true;
                    ensureClauses = {
                      login = true;
                    };
                  }
                ];
              };
            };
          };
        };
      };
  };
}
