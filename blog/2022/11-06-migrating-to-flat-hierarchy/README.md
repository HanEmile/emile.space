# migrating-to-flat-hierarchy

As with every good blog, the only content is in regard to the blog itself, so I'm noting some stuff here that I've been thinking about.

:::toc

## the current structure

So currently, [emile.space](https://emile.space) is built up in a tree like structure: you can navigate it by entering a "node" (for example "blog") and from there on access futher child nodes. While this is really nice for browsing around, It's kind of weird for editing purposes.

## the problem

Now imagine you're editing a page and realize "well, I've already got that page somewhere else". Weird right? Like: shouldn't you've been editing that page in the first place? Well, in what I'm currently thinking about: yes.

## the first solution

Well, instead of having some folder structure which contains a README.md in each folder, I'd like to have a single folder containing files with the name of the individual files dictating what the're about.

> /projects/abc/README.md

becomes 

> abc.md

Now this itself isn't a problem, but there is a problem when thinking of doing this after having already created a whole ecosystem in another format...

## dead links

When changing the format of the page, we should consider keeping old links from external resources functional. By changing the layout from a tree to some kind of flat system, we'd loose the links. The solution is to first spider the site in order to identify what we can "reach" in the first place for then creating a mapping from the "old" to the "new" structure.

## store

The store should contain all the pages with profiles linking to these pages creating the actual structure.

> store/blogpost1/README.md
> store/blogpost2/README.md
> store/blogpost-private/README.md

> profiles/public/blog/blogpost1 -> store/blogpost1
> profiles/public/blog/blogpost2 -> store/blogpost2

> profiles/private/blog/blogpost-private -> store/blogpost-private

When creating the page, a parser should go over all pages, scrape the profile the page is in from the yaml metadata (so each README.md) should contain a section on the top with the following (and possibly more) information:

> name: abc
> date-published: 2023-08-26T18:21:23
> date-modified: 2023-08-26T18:21:29
> profiles: [public, private]
> ...


