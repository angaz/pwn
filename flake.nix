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
        overlayAttrs = {
          inherit (config.packages)
            pwnAPI
            pwnClient
              ;
        };

        packages = {
          pwnClient = pkgs.stdenvNoCC.mkDerivation {
            name = "pwn-client";
            src = ./client/dist;
            phases = [ "unpackPhase" "installPhase" ];
            installPhase = ''
              mkdir -p $out
              cp -r $src $out
            '';
          };
          pwnAPI = pkgs.buildGo122Module {
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
            bun
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
            };
          };

          config = mkIf cfg.enable {
            systemd.services = {
              pwnAPI = mkIf cfg.api.enable {
                description = "PWN API server.";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];

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
            };

            services = {
              nginx = {
                enable = true;
                upstreams.pwnAPI.servers."${apiAddress}" = { };
                virtualHosts."${cfg.hostName}" = mkMerge [
                  cfg.nginx
                  {
                    locations = {
                      "/api/" = {
                        proxyPass = "http://pwnAPI/api/";
                      };
                      "/" = {
                        root = "${pkgs.pwnClient}";
                        autoIndex = true;
                      };
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
