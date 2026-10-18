let
	pkgs = import <nixpkgs> {};
in
	pkgs.mkShell {
	  packages = with pkgs; [ ocaml opam dune ];
	  shellHook = ''
	  	eval $(opam env)
	  '';
	}

