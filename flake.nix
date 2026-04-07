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
