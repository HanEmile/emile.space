# monorepo

:::toc

Well, I've started working on a kind of monorepo, with a few quirks... let me explain.

I love structuring stuff, but I can't really keep one structure alive long enough, as it will die sooner or later, by me just rebuilding another structure. This has led to me switching beteween multiple different ways of sorting, classifying and orderning my files over the last years. Now I tend to separate everything into it's own little folder: here some programming projects, here some files related my site, here some files in which I keep notes and so on.

Now a few days ago, I realized something: everything somehow belongs together. The notes I have stored as some markdown files are somehow connected to the markdown files making up the pages of my site. The pages of my site are somehow connected to the projects I do. So why not throw everything together into one big repo and work with everything there? Well, are arguments against doing this which are fundamentally correct, but I'm trying this out now.

## Individual setups

There are currently three "things" making up the content of the setup, I'll go over them here

## The notes setup

I've come to realize that having a folder of markdown files is fairly nice for taking notes, as it is as pure as it get's. I'm free to do anything I'd like with these, I can easily search through them using rg (ripgrep) and overall, it's just future proof.

Until a few days ago, I wasn't really fond of giving these fancy "note taking apps" a try, as all of them I tried (and I did try a lot of them on one evening about two years ago) were not nice. By "not nice", I mean slow, sluggish, getting in my way, slowing to the whole process of doing something and didn't really convince me of changing my current setup.

Then, on the 7th of july 2021, I spoke with dodo (a cool guy from my local hackspace) and he breifly mentioned that he started using obsidian. I went on and gave it a try (by simply dumping all my markdown notes into a new obsidian "vault") and it worked out really well. This might be becaues of obsidian doing stuff pretty much exactly how I'd expect them to: work on plain markdown files and simply provide a sort of overlay, allowing me to handle the syncronization of the files myself.

## The projects setup

For projects, I've simply got a folder called projects into which I dump all the projects. There isn't really much more to say about it, it's as simple as it gets.

## The site setup

For hosting emile.space, I've gone through multiple iterations and am currently simply hosting a lot of markdown files using mdbook. The file structure is almost exactly as seen in the tree view on the left hand side of the page. In fact, it is so similar to the notes setup, that I went on and created a symlink to the site root from the obsidian vault to see how it works out and it was marvelous. That was when I realized: I can just merge everything and go on from there.

## Syncronization layer

Now I mentioned that I've merged everything, and having everything everywhere (on every device) is quite nice. In oder to do so, twink0r once mentioned that syncthing is awesone. And ohhhhhhhh yes it is!

I went on and setup syncthing

in my wireguard network spanning all my devices on nix1, my Hetzner cloud CPX11 machine
It works amazingly well!