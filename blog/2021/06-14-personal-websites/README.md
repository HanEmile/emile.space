# Personal websites

:::toc

This page, the one you're probably reading this on, is my "personal website". But what does that even mean?

Well, on a technical level, I'm hosting a web server you can make requests to receiving information. This information can be anything, but mostly some text. On another level, you are here for information stored in the pages related to a specific topic.

In the end, this whole "personal website" thing is a short form of me transferring information to you without you needing to contact me. This allows me to share information I have in a more efficient way with the world, so that people can find it on their own or I or others can direct them to specific information.

## The actual hosting

So now that we've got the "whay host stuff" out of the way, let's get to one of the topics I kind of hate: the how.

The information can be presented in multiple ways. In the end, I've got a few files containing the raw information and want it to look kind of okay. There are infinite ways of presenting this, but I (at the time of writing this), just took the mdbook project, gave it all my markdown files, wrote a small script to build it and push it to a server that hosts the resulting build artifacts.

Now this all works, but having Identified what I've done here, I'd like more insight.

## Insights

Insight can mean a few things. The insight I'd like to have is for example page level metrics.

Such metrics might be:

- How long to people have the page open?
- How many people have viewed a specific page?
- Until what point do people read the blobs?

## Restructuring

I'm not the person that likes to stand still on a working system. I love to optimize eveything and can't really stay on a point. That's why I've played around with so many systems in the past and have learn, or at least tried out, so many tools, frameworks or other kinds of software.

Since december 2019 (18 months as of writing this post), I've been using NixOS as my primary system, and fully embrace the whole ecosystem. I just kind of like it and would like to build some kind of "personal website" in a similar way. For this to work, I'll need to restructure my current setup.

## Goals

The end goal is to provide content for people, so that I don't have to explain everything again and a again getting bored. I'd also like a system that is fun to work with without to many headaches.

### The Idea

As with the /nix/store, I'd like to build an immutable /emile.space/store directory, into which all the post I write get thrown into. The input articles could reside somewhre on the system, but when building the page, the articles get modified and inserted into the store for further usage.

I'm thinking of a page that allows me to create profiles containing symlinks to the pages in the store such as the one defined in the /run/current-system/sw/bin on NixOS systems. Now you might ask yourself: Why? Well, with such profiles, I could expose the webserver and handle requests according to users, so If your a user accessing the instance of the webserver in my private wireguard network, you might reach the server as a different "incoming user" and thus get mapped to a specific "profile" and thus get different results (keep in mind: this is just an Idea, I've still gotta find out how good (and if at all) this works).

## Finding out the current state

Now for backwards compatibility reasons, I'd still like to inject some kind of file informing the system, that if a user accesses an old path, they should be redirected to the new /emile.space/store/... path.

For this, I'm probabbly simply going to spider the page using gospider.

## Building the new system

So the idea is (fairly) simply imho, building it should be quite fun. As I've started doing stuff in Rust. All of this should be packaged in a nix-module and I'd love to play around with nix-channels a bit, as hosting one on my one sounds like fun (although I've read some stuff regarding flakes and I'm currently still unsure if that's the way to go. It still seems to be in the very early stages, so I'll wait a bit for that).

## Layouts

I'd prefer building the whole system in a way that allows me to have multiple layouts or "themes".

### book style

+------------------------------------------------+
| 1   |             | askjdh |             | 1   |
| 2   |             | asd    |             | 2   |
| 3   |             |        |             | 2.1 |
| 4   |             | asda   |             | 2.2 |
| 5   |             | asd    |             | 3   |
| 6   |             |        |             | 4   |
| 7   |             | Asdas  |             |     |
|     |             | oius   |             |     |
|     |             | oiaus  |             |     |
+------------------------------------------------+


On the left: an mdbook like meta navigation bar containing defined links to resources in the current profile.

In the middle: The actual content.

On the right: the table of contents (in wide screen mode), built from the headings in the file.

### MAN-style


+------------------------------------------------+
| title              <path>                 date |
|                                                |
| SECTION                                        |
|         8 spaces free, then the content        |
|                                                |
| SECTION                                        |
|         8 spaces free, then the content        |
|                                                |
| title              <path>                 date |
+------------------------------------------------+


## Architecture

As mentioned before I'd like a setup similar to the profiles in the nix-store.

In my case, this would look like this:

Resources

> /emile.space/d3642bae...-blogpost-nixctf/
> /emile.space/1a2f0f7a...-talk-2021-betreutes-hacken/
> /emile.space/6a50e9a7...-writeup-2020-nahamconctf-full-leak/


My idea here is to treat the resources like binaries. Like in the nix store, executing a binary by providing the whole path isn't really nice and adding every single resouce to the "PATH" also isn't really nice, so there needs to be a better way. The nix store manages this in profiles. The profiles contain symlinks to "activated" packages, the analogy can be transferred here in a way that published resources can be seen as "activated". This would mean that if I've got a resource that I'm currenly writing, I can add it the the "draft" profile, allowing me to see it, but not others (I'll have to figure out how to handle authorization and how to filter what entities can access that profile, but that's a problem for later).


Profiles

> .
> ├── 1ea51c06...-writeup-2020-nahamconctf-full-leak
> ├── 3435e849...-blogpost-nixctf
> ├── 9ef931a0...-talk-2021-betreutes-hacken
> └── profiles
>     ├── draft
> 	│   └── writeup-2020-nahamcon-full-leak ->
> /emile.space/1ea51c06...-writeup-2020-nahamconctf-full-leak/
>     └── published
> 		├── blogpost-nixctf -> /emile.space/3435e849...-blogpost-nixctf/
> 		└── talk-2021-betreutes-hacken ->
> /emile.space/9ef931a0...-talk-2021-betreutes-hacken/


Now can we drive this even further? Can we use nix itself for this, creating packages from our articles that can then be referenced? Well, ... yes.