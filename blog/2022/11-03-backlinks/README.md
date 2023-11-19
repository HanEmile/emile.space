# backlinks

Backlinks are amazing, but I haven't implemented them yet. Let's see what I'd
need to do...

:::toc

## intro

So, backlinks are just links from other pages to the page you are currently on. If I link another page to this page, There could be a section containing these links.

## setting up backlinks

The algirithm can be quite simple:

> for file in files:
>   for link in file:
>     append file.name to link.target.file

So if we've got a file structure like the folliwing (with the links being indented):

> .
> ├── A
> │   └── B
> ├── B
> ├── C
> │   └── B
> ├── D
> └── E
>     └── A

(A and C link to B, E links to A), we would go through all the files and look at the links. For example if we're at post "A", we'd see that it links to "B", so we append "A" to "B" (links are added to a .backlinks file, you'll see why later):

> .
> ├── A
> │   └── B
> ├── A.backlinks
> │   └── E
> │
> ├── B
> ├── B.backlinks
> │   ├── A
> │   └── C
> │
> ├── C
> │   └── B
> ├── C.backlinks
> │
> ├── D
> ├── D.backlinks
> │
> ├── E
> │   └── A
> └── E.backlinks

## webmentions

When a page is mentioned somewhere on the interwebz™, a request can be sent to
that page informing it that it has been linked to. This adds another layer to
the whole backlinking system: internal and external backlinks.

By using the backlinks file as a sort of intermediate representation in the
build process (raw markdown files -> companion files with further meta info ->
output format), we can add content there dynamically and also store this
longterm for offline/future reference.
