let
	# NOTE: unpinned — tracks whatever <nixpkgs> the local nix channel points
	# at. Pinning (e.g. via a locked nixpkgs tarball/flake) would make builds
	# reproducible across machines but has not been done yet.
	pkgs = import <nixpkgs> {};
in
	pkgs.mkShell {
	  packages = with pkgs; [
	  	ocaml opam dune            # vokobe2 site generator
	  	python3                    # content scripts (stdlib only)
	  	python3Packages.pyosmium   # extract-map-cache.py
	  	osmium-tool                # fetch-osm-dataset.sh, extract-map-cache.py
	  ];
	  shellHook = ''
	  	eval $(opam env)
	  '';
	}
