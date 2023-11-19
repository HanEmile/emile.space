# web of trust for social groups

A problem arising from time to time in larger groups are bots. Bots themselves can be quite amazing additions to groups, but they can also be weird when joining the group uninvited.

The chaosdorf-public telgram channel had this problem from time to time, when people entered the group and were always first asked if they were a bot or not. This is quite a weird behavour imho, so I'd like to propose another way of handling this situation:

Now bear with me, as this might sound terrible and it might actually be, but I'd like to put it in words in order to get a better idea of how bad this might be.

So the plan would be to build some kind of "common groups" system. Discord does this, as when a person enteres a discord server, you can view your mutual servers with the person. This is a feature matrix is for example missing (telegram has this afaik), and could be implemented somehow.

Now if a bot joined the group and I am not in another group with the bot, I can't evaluate how likeley it is, that this bot is weird or not. In order to make this accountable, I'd like to see how many other people in the group are connected to the bot. Now this poses a lot of issues, as people might not want to be associated with a specific bot or so, so this should only be a feature in larger groups.

In order to kind of solve this, I'd suggest that the bot should have a number
(that is still to be named) that can be calculated like this:

> amount of groups in common with all members in the group / amount of members in the group

people could also opt-in to this in order to add information to the system
