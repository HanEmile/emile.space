# interpaleki

:::toc

the static site generator building the pages my website consist of is really unimportant on the one hand, but on the other hand it is really important to me.

I don't know why, but I like to have complete control on how the page is built while understanding everything that is done. That is why I've build this little static site gen, although interpaleki is not the final form.

In the end, I'd like to use the luno language I'm currently building to create this site. For this, I first need to build luno. Now we've got a problem: As the journey of building this language should be documented (or better: I want to document it), I need some intermediate solution for hosting the pages.

An this is where interpaleki comes in.

## structure

Mainly, we've got one input directory and one output directory. The files from the input directory get converted to html and copied to the output directory.

One of the main features of this page is the navigation. The generator takes into account tha path a page is in and goes through all children of that path and processes a list of their children. Integrating this into the UI makes it easy to jump to a lot of other pages from the page you're on.

For example, say your on the following page:

> project / lun / ecosystem

Hovering over one of the items shows all their children, so for example, we could easily jump to the blogs page by hovering over "project" and selecting blog. Or if we want to view another project, we can hover (or click if on mobile) the "lun" element and select the project we want to view.

## code

The whole generator (as of writing this) consists of 225 lines of python3, of which 156 are code 30 lines of comments and 39 blank lines. Fairly small right?