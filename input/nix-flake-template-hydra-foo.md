(meta
  (tag "blog" "nix")
  (published "2025-02-23")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag" "published")
)

# nix flake template hydra foo

(toc)

So I've been playing around with nix flakes. To be precise, I've got templates defined which contain packages and want those packages to be available from within the "main" flake.

```
//flake.nix
//nix/templates/abc/flake.nix
//nix/templates/abc/def/default.nix
```

(`//` denotes the root of the repo)

In the above, the template `abc` contains a flake and a package called `def`. Now when initializing the template, the template can use the package def.

The template itself can be defined like this:

```
{
 
  ...
  
  outputs = {}: {

    ...
    
    templates = {
      abc = {
        description = "An example template";
        path = ./nix/templates/abc;  
      };  
    };
 
    ...
   
  }  
}
```

Now the template can be used using `nix flake init -t .#abc`

Let's say the flake in the template (`//nix/templates/abc/flake.nix`) has a package def. We need to include that in the main flake if we want to include it in the hydraJobs for hydra to build it. 

## hydraJobs

The `hydraJobs` key in the `outputs` of the flake defines what hydra will build. My goal was to build the templates, so I defined a template-packages function (described below in more detail) that takes the templates (`self.templates`) and provides them to the function, which imports the template flake and returns an attribute set of the packages defined within that flake.

```
      hydraJobs = {
        inherit (self) packages;

        # This is the interesting part
        templates = template-packages self.templates;

        # nixosConfigurations = ...
      };
```

So how does the function template-packages work?

### function definition

First, let's look at how it has to be defined (I despise when blogposts skim over these small, yet helpful for beginners, informations):

```
{
  inputs = {
    ...
  };

  outputs =
    {
      self,

    }@inputs:
    let
      # FUNCTIONS DEFINED HERE
      template-packages = ...
    in {

      ...

    };
};
```

### template-packages function

Now let's look at the function:

```
     template-packages =
       builtins.mapAttrs (name: value:
         (((import ./nix/templates/${name}/flake.nix)
           .outputs)
           { inherit nixpkgs flake-utils; })
           .packages or { }
       );
```

Line by line:

The function we define is bound to a name using the `=` operator, we call our function `template-packages`, you might call your's something different, this is just useful afterwards for when calling the function

```
     template-packages =
```

Now the function is essentially just a call to the `buildins.mapAttrs` function. We have to provide an attrset (in our case, the templates defined in the flake, namely `self.templates`). mapAttrs takes two values, `name` and `value`. We can then use them to define a new attrset that uses the existing key (being the original name) and a new value.

For example, we could do the following:

```
; nix repl
nix-repl> builtins.mapAttrs (name: value: "a ${name}-${value}") { "abc" = "def"; }
{
  abc = "a abc-def";
}
```

With that knowledge, what we want as keys are the names of the templates, but the values shouldn't be the attribute set of the templates, but the packages defined within their flakes.

For that, we need to import the flake (I'm just realizing that we could use the value to extract the path of the flake, but whatever #TODO).

```
         (((import ./nix/templates/${name}/flake.nix)
```

After importing the flake, we can extract the outputs of the flake (which include the packages) using the `.outputs` accessor.

```
           .outputs)
```

Now outputs itself is a function, so we need to call it providing the args it needs. Calling can be done by providing the attrset with the args (you might want to take a look at the complete code above and shift it around a bit)

Essentially, we've done this: `(import flake) { args }`. The first part can be nested, as we've done it, the second part is an attribute set which is used as the argument to the outputs function. Now instead of writing `{ nixpkgs = nixpkgs; flake-utils = flake-utils; }`, the `inherit` keyword can be used to make this simpler. (And you might have seen something like `{ inherit (pkgs) abc def ghi; }`, that essentially translates to `{ abc = pkgs.abc; def = pkgs.def; ghi = pkgs.ghi; }`)

```
           { inherit nixpkgs flake-utils; })
```

After all of that, we have access to the packages of the template. If there aren't any, we just return an empty attribute set:

```
           .packages or { }
       );
```

At this point, reread the function completely, functional functions can be easier to read backwards, from the inside out or however you feel like today.

## packages

Now in order to build the packages from the templates, one could initialize the templates repo or fetch them from hydra, but how nice would it be to use them directly from the root of the flake? For that, they would need to be included in the flakes `packages`.

Now I've got packages which I've defined which are included as overlays:

```
     packages =
       nixpkgs.lib.genAttrs
         [
           "x86_64-linux"
           "aarch64-darwin"
         ]
         (
           system:
           let
             pkgs = import nixpkgs {
               inherit system;
               overlays = [
                 (
                   if system == "x86_64-linux" then
                     self.overlays.x86_64-linux
                   else if system == "aarch64-darwin" then
                     self.overlays.aarch64-darwin
                   else
                     null
                 )
                 # some arguments for packages
                 (_: _: { inherit naersk; })
               ];
             };
           in {
             inherit (pkgs) vokobe r2wars-web remarvin;
           }
         );
```

What this does is use the `nixpkgs.lib.genAttrs` function to generate the attribute sets for the listed architectures. The let binding contains the definition of `pkgs`, the package set which is the imported `nixpkgs` with overlays applied. I'm just using the overlays defined in my `overlays` flake attribute.

With all of that done, I can define the packages exposed by the flake as:

```
packages =
  ...
  {
    vokobe = pkgs.vokobe;
    r2wars-web = pkgs.remarvin;
    remarvin = pkgs.remarvin;
  } 
```

or just 

```
packages =
  ...
  { inherit (pkgs) vokobe r2wars-web remarvin; }
```

Now for using the template packages, we need to get all the packages exposed from the templates and fit them into the system expected by `packages`. I'd say let's just reuse the `hydraJobs` function from before, but hydraJobs takes a nested attribute set and doesn't care how it's built up, while `packages` want's an attribute set in which the architecture is defined and then whithin that, the packages.

So we need to define a new function for doing exactly that.

In the end, I just want to use something like this:

```
packages =
  ...
  { inherit (pkgs) vokobe r2wars-web remarvin; } // mergedTemplatePackages system
```

Which takes all the templates, looks up their system, then merges that into a fitting attribute set and then merges that into the packages

### merged-template-packages

In the let binding after the outputs attrset [described here](#template-packages-function), let's add another function doing that:

```
      merged-pemplate-packages =
        system:
        let
          lib = nixpkgs.lib;
        in
        lib.foldl (
          acc: tplName:
          let
            tplPkgs = templates.${tplName}.${system} or { };
            prefixed = lib.mapAttrs' (pkgName: pkg: lib.nameValuePair "${tplName}-${pkgName}" pkg) tplPkgs;
          in
          acc // prefixed
        ) { } (builtins.attrNames (template-packages self.templates));
```

Once again, let's go through it bit by bit:

First of all, we define a function and bind it to the name `merged-template-packages`. The function takes a system, such as `aarch64-darwin` or `x86_64-linux` as it's only argument.

```
      merged-pemplate-packages =
        system:
```

Next, a let bindings defines the `lib`, this is just a shorthand for us, as we can now just use `lib` and don't have to write `nixpkgs.lib` everywhere (I've got an own lib which is also bound to lib, so this is necessary in my case, but might not be in your case);

```
        let
          lib = nixpkgs.lib;
        in
```

Now the main part: merging all the packages in the right way:

You might want to take a look at the whole thing now, but let's go over the functions used:

```
        lib.foldl (
          acc: tplName:
          let
            tplPkgs = templates.${tplName}.${system} or { };
            prefixed = lib.mapAttrs' (pkgName: pkg: lib.nameValuePair "${tplName}-${pkgName}" pkg) tplPkgs;
          in
          acc // prefixed
        ) { } (builtins.attrNames (template-packages self.templates));
```

Foldl is described like this in the [nixpkgs](https://nixos.org/manual/nixpkgs/stable/):

```
foldl op nul [x_1 x_2 ... x_n] == op (... (op (op nul x_1) x_2) ... x_n).
```

So we can apply an operation on a value, and then apply that operation again on the result of the first application, and so on. We need to provide an initial null value, in our case the empty attrset `{}`.

The list of values we provide to call the foldl function on is provided by `builtins.attrNames` called on the attribute set created using the [template-packages](#template-packages-function)

The fold function itself takes two values: `acc` and `tplName`. Using a let binding, we can puzzle together the value we want:

```
          let
            tplPkgs = templates.${tplName}.${system} or { };
            prefixed = lib.mapAttrs' (pkgName: pkg: lib.nameValuePair "${tplName}-${pkgName}" pkg) tplPkgs;
          in
```

`tplPkgs` just creates an accessor the the template and a specific architecture.

`prefixed` defines an attribute set with the template and the package. 

This all get's put together using foldl into an attributeset that can be used by `packages`.

# nix flake show

Using `nix flake show`, one can view the contents of a flake and see how $stuff is named:

This means we can build packages using `nix build .#goapp-frontend`.

```
; nix flake show
git+file:///Users/emile/hefe
├───darwinConfigurations: unknown
├───deploy: unknown
├───hosts: unknown
├───hydraJobs
│   ├───packages
│   │   ├───aarch64-darwin
│   │   │   ├───goapp-frontend: derivation 'frontend-0.0.1'
│   │   │   ├───goapp-frontend-docker: derivation 'docker-image-frontend.tar.gz'
│   │   │   ├───r2wars-web: derivation 'r2wars-web-0.1.2'
│   │   │   ├───remarvin: derivation 'remarvin-0.1.1'
│   │   │   └───vokobe: derivation 'vokobe-0.1.3'
│   │   └───x86_64-linux
│   │       ├───goapp-frontend: derivation 'frontend-0.0.1'
│   │       ├───goapp-frontend-docker: derivation 'docker-image-frontend.tar.gz'
│   │       ├───r2wars-web: derivation 'r2wars-web-0.1.2'
│   │       ├───remarvin: derivation 'remarvin-0.1.1'
│   │       └───vokobe: derivation 'vokobe-0.1.3'
│   └───templates
│       ├───ctf
│       └───goapp
│           ├───aarch64-darwin
│           │   ├───frontend: derivation 'frontend-0.0.1'
│           │   └───frontend-docker: derivation 'docker-image-frontend.tar.gz'
│           ├───aarch64-linux
│           │   ├───frontend: derivation 'frontend-0.0.1'
│           │   └───frontend-docker: derivation 'docker-image-frontend.tar.gz'
│           ├───x86_64-darwin
│           │   ├───frontend: derivation 'frontend-0.0.1'
│           │   └───frontend-docker: derivation 'docker-image-frontend.tar.gz'
│           └───x86_64-linux
│               ├───frontend: derivation 'frontend-0.0.1'
│               └───frontend-docker: derivation 'docker-image-frontend.tar.gz'
├───nixosConfigurations
│   ├───chusuk: NixOS configuration
│   ├───corrino: NixOS configuration
│   ├───hacknix: NixOS configuration
│   ├───lampadas: NixOS configuration
│   ├───lernaeus: NixOS configuration
│   └───mail: NixOS configuration
├───nixosModules
│   ├───default: NixOS module
│   └───x86_64-linux: NixOS module
├───overlays
│   ├───aarch64-darwin: Nixpkgs overlay
│   ├───default: Nixpkgs overlay
│   ├───unstable: Nixpkgs overlay
│   └───x86_64-linux: Nixpkgs overlay
├───packages
│   ├───aarch64-darwin
│   │   ├───goapp-frontend: package 'frontend-0.0.1'
│   │   ├───goapp-frontend-docker: package 'docker-image-frontend.tar.gz'
│   │   ├───r2wars-web: package 'r2wars-web-0.1.2'
│   │   ├───remarvin: package 'remarvin-0.1.1'
│   │   └───vokobe: package 'vokobe-0.1.3'
│   └───x86_64-linux
│       ├───goapp-frontend omitted (use '--all-systems' to show)
│       ├───goapp-frontend-docker omitted (use '--all-systems' to show)
│       ├───r2wars-web omitted (use '--all-systems' to show)
│       ├───remarvin omitted (use '--all-systems' to show)
│       └───vokobe omitted (use '--all-systems' to show)
└───templates
    ├───ctf: template: A basic ctf env with pwn, rev, ... tools
    └───goapp: template: A basic golang service
```
