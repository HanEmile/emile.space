# mobesi

The first attempt at writing a web application proxy that is supposed to be used in a team.

(I'm first going to write down some thoughts here, until I'm in a state were I'm confident what I can write a lot of code).

:::toc

## Collaboration

When currently looking into a page, all inforamtion is stored locally on your machine. While most tools have embraced collaboration, information isn't shared. Now one could simply install some proxy on a vm somewhere and tell everyone to proxy their traffic through there, this isn't really practical.

In the end, what I imagine would be a proxy that allows you to view the results locally (requests send and so), but for all people of the team. You should still be able to use it in "singleplayer" mode, but should also be able to function as a "shared host" that syncronizes the state of the application with other people.

## Scenarios

There are three scenarios (that I've thought of as of now):

### all people in the same network (local)

The simplest one: we're all in the same network and we all want to work with each other. Open some port in your firewall allowing your instance to communicate with another one.

### all people in the same network (VPN)

Almost as simple (depending on how the VPN is setup).

### all people in the same network (Internet)

Also fairly simple, although they're probably going to be problems due to NAT or so (let's go public v6 only?).

## Timeline

2022-01-29: start of writing this down