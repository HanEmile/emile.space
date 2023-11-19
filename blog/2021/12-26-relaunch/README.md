# relaunch

:::toc

As with every blog, website or project I do, stuff launches, goes up pretty fast and then falls a long time without control.

This has happened with this site and I've taken it upon myself to make it a little bit more stable.

For this, I've simplified it as much as possible, making it as fast as possible (this is one of my most important requirements at the time of writing). In addition to the end result loading fast, I decided that the build process should be fairly fast as well.

For this, I've created a small system in which I've got markdown files which are converted to html. There isn't any kind of sophisticated markdown parser or so contained within this system, everything is just kept as simple as possible (without going overboard with the simplicity, as in: I've still got titles and subtitles, but no fancy stuff which would require me to parse the markdown further such as bold or italic text, markdown links or so).

## building

In order to build the site, I execute the build script which does the following:

; rm -rf out && python3 src/gen.py ./in | tee out.log

- Removes existing build data, essentially creating a new page fromd the ground up every single time (we can do this, as the page is so small that this isn't really a problem. It might become one in the future, but I'm not seeing that now and by the time it may become a problem, I'm probably be using another system, but who knows)
- Executes the gen.py script which generates the html files from the markdown files contained in the input directory ./in
- Stores a log of the gen.py output in out.log for at least having logs when things get weird

## synchronizing

Having a local copy of the page on my computer, I can synchronize it with the remote server. Doing this can be really fancy, bit I'm just using rsync to synchronize the files to the remote server which services the files in the directory statically:

; rsync -avz --delete out/* root@nix1:/var/www/emile.space/

## navigation

Navigating a page is quite essential for the usability of the page. A page without links to other pages is not enjoyable, as although the content might be interesting, exploring what the page has to offer isn't that fun.

For this, I've just reused an existing concept: folders. The navigation is kind of based on how a graphical file explorer on most popular operating systems works. You select a folder you want to enter and then enter the folder.

The special part is the rest of the navigation or the "exploration" part: you can hover over the parent folders of the current folder allowing you to explore what's in them. This allows you to quickly access "close" objects as well as "far" objects.