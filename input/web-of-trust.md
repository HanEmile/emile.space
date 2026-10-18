(meta
  (tag "blog")
  (published "2024-12-16")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag" "published")
)

# web of trust

> Have some thoughts, here in text form, this is quick and dirty, but my point of view

Due to the 38c3 ticket sale, I've once again done a deep dive into the whole "web of trust" topic. The goal is to buy or sell a ticket without getting scammed, without an intermediate that is to be trusted.

So say I want to buy a ticket. Ideally, I could find someone selling a ticket, contact them, communicate on the formalities (price, location of exchange, ...) and finally have a ticket.

So what could go wrong?

- The seller could sell the same ticket to multiple people, so the first person that get's into the event is fine, but the rest that try to redeem the ticket have a problem
- The seller could just ghost the buyer after having received the money
- the seller could sell the buyer a fake ticket that doesn't work

Now instead of solving all of this, let's assume the seller actually has good intentions and we just want to check if the seller is "legit" (as in: people might know them and we've got a "path" to them)

This could be done using social media.

Say you've got an activitypub account and the seller has one, most activitypub instances publish information on how they are following and who they are followed by. Using that information, a path from the buyer to the seller could be built.

Adding information such as "yes, I know this person, I follow them and they are legit" in addition to the whole "I'm following their content" would help build such a web (completely decentralized!). Now this is literally just the same as in the "real world" when talking with people, but digitally, so nothing new, but might help in finding legit people.

Queries in this graph could include a limit on hops, so you could keep within your direct group and expand from there on. While writing this, I just realized that that would also be an interesting slider on a timeline: show me the people I'm following or show me the people being followed by the people I'm following.

Essentially, the concept of "following" could be made more granular in order to allow this to work, as otherwise, you'd quickly have a full mesh.
