# Nix CTF

:::toc

A short blogpost detailing the setup used to host a fairly spontaneous CTF at the Location not included 2020 hosted by das labor, the hackspace in Bochum.

## Getting started

So, in order to host a CTF, there are two main groups of services needed: a Scoreboard and some Challenges.

The Scoreboard is there to track the amount of points each team has got in order to rank them.

The Challenges are accessible independantly allowing them to be run literally everywhere.

Having these two groups setup, a basic CTF-event can be held. It is important to note here, that these two can (in theory) run completely independant from each other, the only shared knowlege should be the name of the challenges and their flags hash.

Let's get into the detail of what there is to take care of and how I did this for the CTF.

## The Scoreboard

The scoreboard should rank the teams, thus count amount of points that they have obtained by solving challenges... or should it be done differently?

Let's say you've built challenges and started defining the amounts of points a challenge is worth on your own. The result is biased, due to you knowing the solution and thus possibly misjudging the challenge difficulty.

A possible popular solution to this is called "Dynamic Scoring". Using this concept, each challenge is worth a fixed amount of points from the beginning and the amounts of points the challenge is worth sinks with the amount of teams solving the challenge. For example, the challenge may be worth 500 points withouy any team having solved it, but if a team manages to solve the challenge, the amount of points the challenge is worth drops to 499. With another solve, the points drop eaven further to 484 and so forth (we're getting to how these points are calculated in a minute!).

### Dynamic scoring

So when implementing dynamic scoring, we need to keep track of how often a challenge was solved and the challenges the individual teams have solved. Using this, we can calculate the amount of points a challenge is worth:


> MAX     : 500      No solves
> MIN     : 100      DECAY solves
> DECAY   : 15       Amount of solves needed in order to reach minimum points
> ALG     :          (((MIN - MAX)/(DECAY ^ 2)) * (solves ^ 2)) + MAX

- MAX defines the amount of points a challenge is worth without any solves.

- MIN defines the amount of points a challenge is atleast worth, the challenge should never be worth less.

- DECAY defines how many teams have to have solved the challenge, so it is worth MIN points.

- ALG is the algorithm used for this, we insert the values defined above here (and the amount of solves this challenge has got) in order to get the amount of points the challenge is worth.

If you wan't to try this out, head to the scoreboard-repo, set it up and play around with it!

## The challenges

Having challenges running is important, having running challenges even more important and having challenges that keep the players in their bounds is really important (Events in the past have shown that this can end well, but we don't want to risk anything).

Step 1: build a challenge:

I'll split this up into the two main categories each challenge can have (no not pwn, web, cry or so...). These categories are static challenges and dynamic challenges.

### Static

Static challenges are challenges, for which the player only need some files, for example in a lot of crypto challenges, the players are given files, but don't get any interactive service they can interact with.

Static challenges can be hosted almost anywhere, the important part here is that the players get access to the location the challenges are hosted, and that the host is capable of hosting challenges potentially a lot of players.

### Dynamic

Dynamic challenges on the other hand are challenges that the players interact with. This means that as an organizer, you host the challenges somewhere and the players need to interact with the service you've hosted.

The best example for this category is the pwn category in most CTFs: players get a binary, exploit it locally and then run the exploit on a server provided by the orgainzers.

The clue here is to have the service exposed strongly isolated. All in all: the player should be able to play the challenge, but not pivot through your network.

## Isolation

Isolation can be achieved in many ways. For example, limiting the stuff the user can do very strictly. This might as well be "don't build broken software", so we need a better way to do this...

First of all, let's define what we've got: Let's say we've build an interactive challenge (for example one that might look like a python shell). We allow the user to enter stuff and exec it. The user can now in theory do everythig they want on the host the service is running on. In order to prevent this, we could insert the service into a container or so, but containers don't automatically mean security...

Luckily, we're not the first one's organizing such a CTF, so people have built stuff that might help, for example nsjail. Nsjail is a "A light-weight process isolation tool [...]" allowing us to isolate our challenge. Even better, njail offers a lot of stuff making hosting such vulnerable challenges great: It can host a binary, wait for a connection and upon recieving a connection run some binary or so connecting the network io with stdin and stdout.

From the examples at the bottom of the nsjail man --help page:

Wait on a port 31337 for connections, and run /bin/sh


> nsjail -Ml --port 31337 --chroot / -- /bin/sh -i


That's exactly what we need to host a ctf: an service that, opon connecting to, executes a binary. Gone are the times of starting a completely new container for each participant (at least for most challenges)!

Hosting a challenge in the CTF looked a bit like this:


> nsjail -Ml \
> 	--hostname host \
> 	-T /dev \
> 	-R /dev/urandom \
> 	-R /dev/pts \
> 	--port 9999 \
> 	--user 1337 \
> 	--group 1337 \
> 	--chroot / \
> 	--cwd /home/user \
> 	--stderr_to_null \
> 	-E LANG=C.UTF-8 \
> 	-E TERM=xterm \
> 	-E FLAG=flag{******************} \
> 	 -- \
> 	/usr/bin/python3 /home/user/main.py


But all of this still has to be hosted, so let's get into that a bit...

## Infra

### Container foo

First of all, all dynamic challenges should be containerized for example as below:


> FROM nsjailcontainer
> 
> RUN useradd user
> RUN apt-get update
> 
> RUN apt-get install -y python3
> 
> ENV flag="flag{****************}"
> COPY main.py /home/user/main.py
> 
> ENTRYPOINT [ "/bin/nsjail" ]


As the entrypoint is set to nsjail, we can provide the nsjail arguments when running the container, but let's first look at how nixos comes into this, as it does play a crucial role...

### Hosts

For this tiny CTF, there was one host (although I'd reccommend to use atleast two hosts in order to have the scoreboard on a seperate host).

The tiny CX11 from hetzner was used for this, and my laptop was used for deploying it's config using nixops.

The host is running NixOS allowing us to configure the system only using it's configuration.

### Nixops

Nixops can be used to deploy nixos configurations to other hosts. (I wrote a short post here describing the process, du the documentation skipping any kind of introduction).

This allows us to define the config for the remote host on our machine in the config and use nixops to deploy this config to the remote host running the services and/or the scoreboard.

TL;DR of the nixops blogpost:

Create a target.nix file containing information on where the host is running


> {
>   target = { config, pkgs, ... }: {
>     deployment.targetHost = "123.122.111.110";
>   };
> }


Create a config.nix file containing the configuration for that host:


> {
>   network.description = "nixops example";
> 
>   target = {config, lib, pkgs, ...}: {
>   
>   # insert complete config here
>   
>   };
> };


Create the deployment:


> ; nixops create ./target.nix ./config.nix -d target

> created deployment ‘6883071e-df3c-11ea-bd95-0242dcf913a0’
> 6883071e-df3c-11ea-bd95-0242dcf913a0


List your deployments:


> ; nixops list
> +--------------------------------------+--------+------------------------+------------+------+
> | UUID                                 | Name   | Description            | # Machines | Type |
> +--------------------------------------+--------+------------------------+------------+------+
> | 6883071e-df3c-11ea-bd95-0242dcf913a0 | target | Unnamed NixOps network |          0 |      |
> +--------------------------------------+--------+------------------------+------------+------+


Deploy!


> ; nixops deploy -d target
> ...
> target> deployment finished successfully


### Challenge definitions

In order to host our challenges, we need to somehow instruct nixos to fetch the docker images containing the individual challenges from somewhere and run them. For doing this, I setup a small directory structure in order to split up the config a bit:


> .
> ├── config.nix
> ├── target.nix
> └── modules
>    ├── boot.nix
>    ├── ctf
>    │  ├── chall
>    │  │  ├── hashy.nix
>    │  │  ├── ...
>    │  │  └── visible.nix
>    │  └── scoreboard
>    │     ├── postgres.nix
>    │     └── scoreboard.nix
>    ├── ctf.nix
>    ├── hardware-configuration.nix
>    ├── ...
>    ├── services
>    │  ├── ...
>    │  ├── nginx
>    │  │  ├── ctf.emile.space.nix
>    │  │  ├── ...                   
>    │  │  └── static.emile.space.nix
>    │  ├── ...                      
>    │  └── nginx.nix
>    ├── services.nix
>    ├── timezone.nix
>    ├── users.nix
>    └── virtualisation.nix


First of all, let's look into config.nix:


> {
>   network.description = "nixops example";
>   
>   target = {config, lib, pkgs, ...}: {
>   
>   imports = [
>     ./modules/boot.nix
>     
>     ...
>     
>     ./modules/ctf.nix
>     ./modules/services.nix
>   ];
>   
>   system.stateVersion = "20.03"; 
>   
>   };
> };


So we import ctf.nix, let's look into there:


> {
>   imports = [
>     ./ctf/chall/visible.nix
>     ...
>     ./ctf/chall/hashy.nix
> 
>     ./ctf/scoreboard/postgres.nix
>     ./ctf/scoreboard/scoreboard.nix
>   ];
> }


This imports all the container definitions, let's look into a single challenge container, as this is the part that get's interesting:


> {
>   virtualisation.oci-containers = {
>     backend = "docker";
>     containers = {
>       "abcd" = {
>         image = "abcd";
>         extraOptions = [
>           "--privileged"
>         ];
>         ports = [
>           "9990:9999"
>         ];
>         cmd = [
>           "-Ml"
>           "--hostname" "host"
>           "-T" "/dev"
>           "-R" "/dev/urandom"
>           "-R" "/dev/pts"
>           "--port" "9999"
>           "--user" "1337"
>           "--group" "1337"
>           "--chroot" "/"
>           "--cwd" "/home/user"
>           "--stderr_to_null"
>           "-E" "LANG=C.UTF-8"
>           "-E" "TERM=xterm"
>           "-E" "FLAG=flag{************************}"
>           "--"
>           "/usr/bin/python3" "/home/user/main.py"
>         ];
>       };
>     };
>   };
> }


What we do here, is we instruct nixos to run a docker container using the image with the given name (honestly, it would be practical to just use a private registry here, but due to some time constraints and me not bothering with diving into that rabbit hole, I just build the images and moved them to the host...).

The container is run as privileged which would normally be a huge no-go, but we have to allow nsjail to do it's magic.

We expose port 9990 for the challenge to be accessed on (note: the port in the container is port 9999, as we defined it in the nsjail command).

All challenges, the scoreboard and the database are setup like this.

(Sidenote: There's a lessons learned at the bottom containing information on what could have been better)

### nginx

In order for the scoreboard to be visible at ctf.emile.space, we need a bit of nginx and we can configure it using nixos. First of all, let's looked how it get's imported into the config.nix (I'll keep this a bit shorter):

config.nix imports services.nix
services.nix imports all the services in the modules/services/ folder, including nginx.nix
nginx.nix imports all the virtualhosts defined in modules/services/nginx/ folder, including ctf.emile.space.nix
Ok, so ctf.emile.space.nix contains the definition for an nginx virtualhost:


> {
>   services.nginx.virtualHosts = {
>     "ctf.emile.space" = {
>       enableACME = true;
>       forceSSL = true;
> 
>       locations = {
>         "/" = {
>           proxyPass = "http://127.0.0.1:8000";
>         };
>       };
>     };
>   };
> }


All we do here is to proxy ctf.emile.space to the internal service exposing the scoreboard allowing user to access it.

Overall, I find it quite amazing that nixos allows me to configure everything using this one config format. If you'd like to dive deeper into this and don't know it yet, search.nixos.org is a wonderful page allowing you to browser the packages and config options you can use.

## Meta

When stuff goes wrong, it is normally nice to be in control. For example: when a challenge is broken. The firsy thing should be to remove the challenge from the plage where new players access the challenge, so no new people access it. Another thing might be do disable flag submission for that particular challenge.

For doing all of this, an admin web-interface or so might be really practical, but as minimal as the scoreboard is, as minimal is the solution: a config file that is being watched by viper (config management in go) with sort of hooks that execute given functions upon change. This allows a function to read the config after it has been changed and sync the state of that config to the database.

Using this, we can adjust the active state of a single challenge just by changing it's value in the config. Another thing that might be practical is updating the flag hash.

## Lessons learnt

As promised, a small lessons leart: Overall, things went really well, but here some stuff that was missing:

Updating challenges was kind of weird: due to me having to update the docker images on the host manually, it didn't really work by simply editing the challenge locally, pushing the result to a repo that might use drone as we did last year to build the docker image and push it to a private registry that is then accessd by nixos.

Building the docker images using ordinary Dockerfiles is boring! NixOS offers building declarative docker images that are optimized for caching and stuff like that. I build a minimal image, but didn't get to build the challenges using that technology altough it would have been another step in the pipeline what could have been solved using existing nix-ology :D, I'll try it in the next CTF.