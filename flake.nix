{
  description = "Quarto development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        pandiff = pkgs.buildNpmPackage {
          pname = "pandiff";
          version = "0.8.0";
          src = pkgs.fetchFromGitHub {
            owner = "davidar";
            repo = "pandiff";
            rev = "2631bb939e8031c4feb04a4b76e7df600e442a40";
            hash = "sha256-GLLzfduUlTjeVc6AfifTXGJO/7elHbHv5XZeBdKjN5I=";
          };
          postPatch = ''
            cp ${./pandiff-package-lock.json} package-lock.json
            substituteInPlace package.json --replace-fail '"prepare": "yarn run compile",' ""
          '';
          npmDepsHash = "sha256-VNnrSzmb+gcJO+V6QCQg/IVlsGPrjEg4gIFDEb+7jDM=";
          npmBuildScript = "compile";
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postInstall = ''
            wrapProgram $out/bin/pandiff --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.pandoc ]}
          '';
        };
        pythonPackages = with pkgs.python313Packages; [
          jupyter
          numpy
          pandas
          matplotlib
          ipython
        ];
        rPackages = with pkgs.rPackages; [
          ggplot2
          dplyr
          knitr
          rmarkdown
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              quarto
              pandoc
              pandiff
              texliveMedium
              python313
              R
            ]
            ++ pythonPackages
            ++ rPackages;
        };
      }
    );
}
