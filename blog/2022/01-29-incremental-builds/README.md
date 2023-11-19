# incremental-builds

After having added some content to [emile.space](/) over the last month and having rebuilt it hundreds of times using [vokobe](/projects/vokobe), I'm at a point at which it starts to feel slow.

slow.

> ; ./publish.sh

> real    0m2.860s
> user    0m0.388s
> sys     0m1.620s

At this point, you might think: "Emile, that's not slow", but I do think it could be better.

The thing is: currently, everything is completely rebuild on every build. So every single markdown file is converted to html and rebuilt, even if no changes have been made.

That's just mad.

So, I'm probably going to re-write vokobe in a way that would take incremental builds into account. So if a file hasn't been changed since that last build, it isn't rebuilt.

## Rebuilding

This is actually quite simple, we just need to track the builds:

If we've got three files A.txt, B.txt and C.txt that have been modified like this:

> 2022-01-10 12:57 A.txt
> 2022-01-20 15:32 B.txt
> 2022-01-26 22:03 C.txt

And the last build was on 2022-01-23 at 13:37, we just have to look at all files that have changed since then.

So the file C.txt has changed since the last build, so it has to be rebuilt.

Now another problem are deleted files.

## Deleting

Let's say that since the last build, we've deleted file B.txt. We haven't got that file in our input anymore, so we won't evaluate it or even check the last time it has been built. We do need to do some kind of pass in the end to check if there was an input for all files in the output (assuming we're overwriting the output on every built to represent the current state defined in the input).

## Endword

I'm probably going to do this on 2022-01-29.

2022-01-31: I didn't...