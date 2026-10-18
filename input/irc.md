(meta
  (tag "project")
  (published "2026-09-14")
  (modified "2026-09-14")
  (author "Emile")
  (info "published"))

# irc

(toc)

I'm operating an irc server! Nix source.

Be friendly to each other and HACK THE PLANET!

```
irc.emile.space:6697 #general
```

## minimal bash client

Easily connect and write in emile.space #general:

[irc.sh](irc.go)

```
curl -sL emile.space/irc.sh -o- | bash
```

or to set a nick:

```
curl -sL emile.space/irc.sh -o- | IRC_NICK=acker bash
```

## go bot

A minimal golang based bot:
(This is just a template for further fun)

[irc.go](irc.go)

```
d=$(mktemp -d) && curl -sL emile.space/irc.go -o "$d/irc.go" && go run "$d/irc.go"; rm -rf "$d"
```

## modes

* +C (Disables CTCP): Prevents bot and spam
* +n (No outside messages): Prevents users not in channel to send to channel
* +i (Invite-Only): Requires an invite or matching mask to join.
* +m (Moderated): Only users with voice or operator privileges can speak.
* +t (Topic Lock): Only channel operators can change the topic.
* +k (Key-Protected): Requires a password/key to enter.
* +b (Ban): Blocks specified user hostmasks from the channel.
* +o (Operator): Grants channel management and moderation privileges.
* +v (Voice): Grants speaking rights in a moderated channel.

## services

Provided by the networks:

* NickServ
* ChanServ
* GroupServ
* HostServ

Provided by soju (my bouncer):

* BouncerServ
