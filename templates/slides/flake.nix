{
  description = "Quarto revealjs slides: plate theme, live polls, PDF handouts";

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

        # scheme-medium is short of what the handout format (plate-pdf) needs.
        # Quarto renders callouts as tcolorbox frames with fontawesome5 icons,
        # and plate's own preamble wants titlesec (the page break before every
        # slide heading) and fancyhdr (the logo header and the footer rule).
        # Naming the packages keeps this a few MB rather than the several GB
        # texliveFull would drag in.
        #
        # environ / pgf / tikzfill / listingsutf8 are tcolorbox's own
        # dependencies, listed explicitly because withPackages does not resolve
        # them for you: leave one out and the failure is a missing .sty three
        # levels deep in a LaTeX trace.
        texlive = pkgs.texliveMedium.withPackages (
          ps: with ps; [
            tcolorbox
            fontawesome5
            environ
            pgf
            tikzfill
            listingsutf8
            pdfcol
            titlesec
            fancyhdr
            adjustbox
            microtype
            koma-script
            framed # the handout's highlighted code blocks
          ]
        );
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.quarto # brings its own pandoc
            texlive # ./build --pdf: the handout
            pkgs.python3 # ./render serves the decks with python3 -m http.server
            pkgs.rsync # ./deploy
            pkgs.findutils # the scripts use GNU find's -printf, which macOS lacks
          ];
          shellHook = ''
            # `nix flake init` writes every file without its executable bit, so
            # the scripts arrive as plain files. Put it back.
            chmod +x install-extensions new-week build render deploy 2>/dev/null || true

            # The GitHub-hosted extensions are installed, not shipped: fetch
            # any that are missing (the first time, in a new project). A
            # failure, offline say, warns and leaves the shell usable.
            if [ -x ./install-extensions ]; then
              ./install-extensions || echo "some extensions are missing; run ./install-extensions when online" >&2
            fi
          '';
        };
      }
    );
}
