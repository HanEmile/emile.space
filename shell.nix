let
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
