
{
  description = "Nix package for Peek - SwiftUI previews on a real iPhone";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "peek";
            version = "0.3.0";

            src = self;

            nativeBuildInputs = [
              pkgs.makeWrapper
            ];

            dontBuild = true;

            installPhase = ''
              runHook preInstall

              mkdir -p $out/share/peek
              cp -r . $out/share/peek

              mkdir -p $out/bin

              makeWrapper ${pkgs.python3}/bin/python3 $out/bin/peek \
                --add-flags "$out/share/peek/peek" \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.swift
                    pkgs.swiftpm
                    pkgs.ldid
                    pkgs.openssl
                  ]
                }

              runHook postInstall
            '';

            meta = {
              description = "SwiftUI previews on a real iPhone, built on Linux";
              homepage = "https://github.com/kimikr/peek";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.linux;
              mainProgram = "peek";
            };
          };
        });
    };
}
