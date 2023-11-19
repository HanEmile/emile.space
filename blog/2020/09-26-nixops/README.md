# nixops

:::toc

I had to read more than I'd expect from a project that fundamental, so here's a post describing the process.

## Assumptions

- You've got some server (called "Target" from here on) running NixOS with root-access.
- You've got NixOps installed

## Goal

So the goal we want to achieve is to deploy the config located on the target server from you machine. This means that on you're machine, you've got the config of the target machine (config.nix), as well as a config instructing NixOps where the machine is located (target.nix).

Let's start with the target.nix file, as it is fairly simple:


> {
>   target = { config, pkgs, ... }: {
>     deployment.targetHost = "123.122.111.110";
>   };
> }


All you do here, is define the target nixos should deploy to.

The config.nix file contains the complete configuration (although a partial one should do) of the target system. A caveat here is that the configuration cannot be copied over, but has to be inserted into a predefined scheme:


> {
>   network.description = "nixops example";
>   target = {config, lib, pkgs, ...}: {
> 
>   # insert complete config here
> 
>   };
> };


## Creating the deployment

The deployment can be created using the nixops create command:


> ; nixops create ./target.nix ./config.nix -d target

> created deployment ‘6883071e-df3c-11ea-bd95-0242dcf913a0’
> 6883071e-df3c-11ea-bd95-0242dcf913a0


In this command, we create a new deployment called target using the config files described above as input.

We can now list all deployments using the nixops list command:

> ; nixops list
> +--------------------------------------+--------+------------------------+------------+------+
> | UUID                                 | Name   | Description            | # Machines | Type |
> +--------------------------------------+--------+------------------------+------------+------+
> | 6883071e-df3c-11ea-bd95-0242dcf913a0 | target | Unnamed NixOps network |          0 |      |
> +--------------------------------------+--------+------------------------+------------+------+


As you can see, the deployment was created, but no machine is assigned. Let's deploy something...

## Deploying

Deploying can be done using the nixops deploy command. This will build the machine configuration and copy the paths from the nix-store to the remote nix-store.

The output should look something like this:


> ; nixops deploy -d target
> target> generating new SSH keypair... done
> target> setting state version to 20.03
> target> waiting for SSH...
> building all machine configurations...
> these derivations will be built:
>   /nix/store/75kfw9jq8si7wxvb4g4zq8zxnbixnci9-etc-hosts.drv
>   /nix/store/y6jy6fdxnazal0z7n9bz9rjcdzh0dpdz-unit-nscd.service.drv
>   /nix/store/78vjar6qvvvkvvyk01xdri3ajiafaq37-system-units.drv
>   /nix/store/ycmvrqi6bvdgs0kkckd4fnk4v65g31rw-root-authorized_keys.drv
>   /nix/store/1hg189d7r2h0gfzqdsdjd1dc44y9yi8l-etc.drv
>   /nix/store/hx5bmim1n8d0whl28dpqcwh12d5cw1vb-nixos-system-nixos-20.03.2260.7bb2e7e0f69.drv
>   /nix/store/cilysf8jk7kjvasabml97l17nbic8i5s-nixops-machines.drv
> building '/nix/store/75kfw9jq8si7wxvb4g4zq8zxnbixnci9-etc-hosts.drv'...
> building '/nix/store/ycmvrqi6bvdgs0kkckd4fnk4v65g31rw-root-authorized_keys.drv'...
> building '/nix/store/y6jy6fdxnazal0z7n9bz9rjcdzh0dpdz-unit-nscd.service.drv'...
> building '/nix/store/78vjar6qvvvkvvyk01xdri3ajiafaq37-system-units.drv'...
> building '/nix/store/1hg189d7r2h0gfzqdsdjd1dc44y9yi8l-etc.drv'...
> building '/nix/store/hx5bmim1n8d0whl28dpqcwh12d5cw1vb-nixos-system-nixos-20.03.2260.7bb2e7e0f69.drv'...
> building '/nix/store/cilysf8jk7kjvasabml97l17nbic8i5s-nixops-machines.drv'...
> target> copying closure...
> target> copying 6 paths...
> target> copying path '/nix/store/9dyfcyl838rx0ih8k7a7rpiabwi8y0lk-root-authorized_keys' to 'ssh://root@138.201.190.65'...
> target> copying path '/nix/store/irqfi2l3431p8wa00arg0chdr20ysad6-etc-hosts' to 'ssh://root@138.201.190.65'...
> target> copying path '/nix/store/7nbv0mw6jrrw68bn297kihwdmq0fn3y2-unit-nscd.service' to 'ssh://root@138.201.190.65'...
> target> copying path '/nix/store/f0x5d9s31gxzkbsrnhpqvsqrhz6rryc9-system-units' to 'ssh://root@138.201.190.65'...
> target> copying path '/nix/store/bmxqa2ppi0d43fvp3drx0hgbcq3j5jv2-etc' to 'ssh://root@138.201.190.65'...
> target> copying path '/nix/store/9v8jqh5izq81nb60rzcindc6nr7cqwxx-nixos-system-nixos-20.03.2260.7bb2e7e0f69' to 'ssh://root@138.201.190.65'...
> target> closures copied successfully
> target> updating GRUB 2 menu...
> target> stopping the following units: nscd.service
> target> activating the configuration...
> target> setting up /etc...
> target> reloading user units for root...
> target> setting up tmpfiles
> target> starting the following units: nscd.service
> target> activation finished successfully
> target> deployment finished successfully


A few things happen here:

- A new ssh keypair is created for access to the machine.
- All needed derivations are build
- The closures are copied to the target
- The GRUB menu is updated for displaying the latest generation
- Services are stopped
- The config is activated
- /etc is setup
- The users units are reloaded
- tmpfiles are setup
- The previously stopped services are restarted
- And in the end, the nice messages "activation finished successfully" and "deployment finished successfully" indicates that the deployment has worked successfully!

## Endword

This should have given you a super basic introduction on how to use an existing NixOS setup in NixOps. The current documentation is far from perfect and doing this isn't really as straitfoward as I though it could be. In the end, it works, but the process of getting it to work included more rabbit-holes that I'd like to admit.