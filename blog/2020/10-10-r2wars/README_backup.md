---
title: r2wars
date: 2020-10-10
publish: true
---

# r2wars

:::toc

Over the last few days, I’ve played around with r2wars, a competion typically between two programs that try to survive as much time as possible in a shared memory space. A python implementation of r2wars can be found on <a href="https://github.com/radareorg/radare2-extras/tree/master/r2wars">github</a> as well as a <a href="https://github.com/radareorg/r2wars">C# Implementation</a>.

## What is radare2?

So let's start at the beginning with a question that might help some unfamiliar people understand all of this: what <a href="https://www.radare.org/">radare2</a> actually is. According to Wikipedia,

> "Radare2 is a complete framework for reverse-engineering and analyzing binaries; composed of a set of small utilities that can be used together or independently from the command line.

— <a href="https://en.wikipedia.org/wiki/Radare2">Wikipedia - Radare2</a>

So we can use radare to take apart binaries, but using all the tools included, we can do much more as you'll see next.

> radare2 commands tend to be not so descriptive. If you don't know what a command does, you can append a question mark to the command to get some help. If you know what you want to do, but don't know the command that might be able to do what you want to do, you can use this alias to search through all radare commands interactively:
> 
> "alias r2help="r2 -qq -c '?*~...' --"

## What is r2wars?

Over the last few days, I’ve played around with r2wars, a competion typically between two programs that try to survive as much time as possible in a shared memory space. A python implementation of r2wars can be found on github as well as a C# implementation.

There exist similar forms of games such as <a href="https://en.wikipedia.org/wiki/Core_War">Core Wars</a>, but what makes r2wars different is that the bots can be built in any architecture supported by ESIL <a href="https://radare.gitbooks.io/radare2book/content/disassembling/esil.html%22">Evaluable Strings Intermediate Language</a>, more than 2 programs can run at the same time and cyclic execution cost matters for the turns.

## r2wars in detail

So here we go, some more in detail information on how stuff works:

### Bots

The "players" are bots. A bot is a piece of assembly, written in either x86, arm or mips using either 8, 16, 32, or 64 bit registers. A super simple bot doing nothing but locating itself in memory might look like this: (x86, 32 bits)


> call me
> me:
>     pop eax


Assembling such a bot can be done using rasm2, the radare2 assembler and disassembler tool, as displayed in the listing below.


> ; rasm2 -a x86 -b 32 -f bot.asm
> e80000000058


The bot created can be inspected, by disassembling it again using rasm2 like below.


> ; rasm2 -D e80000000058
> 0x00000000   5      e800000000  call 5
> 0x00000005   1              58  pop eax


### The Arena

So now that you know how to assemble a bot, let's define the "arena" or the shared memory space in which the bots will battle.

### Allocating memory for the Arena

First of all, some memory should be allocated, for two bots, 1024 bytes should be enough. Memory can be allocated by radare as displayed below:


> ; r2 malloc://1024
>  -- How about Global Thermonuclear War?
> [0x00000000]>


By doing this, we allocated 1024 bytes of memory. This is the shared space in which the bots will battle each other.


> [0x00000000]> o
>  3 * rwx 0x00000400 malloc://1024


As you can see, the memory allocated is mapped rwx and consists of 1024 (0x400) bytes.

### Setting up the arena and ESIL

The next step to building the arena is to define the architecture and the size of the registers that should be used:


> [0x00000000]> e asm.arch = x86
> [0x00000000]> e asm.bits = 32


The next step is to initialize the ESIL VM state as well as the VM stack. All radare2 command for editing the ESIL VM are prefixed with ae.


> [0x00000000]> aei 	# initialize ESIL VM state
> [0x00000000]> aeim 	# initialize ESIL VM stack


### Generating initial positions for the bots

The arena is now set up, the next step is to insert the bots into the arena. Selecting where to insert the bots is kind of crucial, because the bots should not be inserted into each other and not to close to the end of the arena (0x400 in this case).

In order to generate a random offsets where the bots can be placed, multiple addresses should be generated in the following way:


> genspace = [0x000, 0x3c0)
> maxbotspace = [0x3c0, 0x400)
> 
> 0x000                        0x340              0x400
> + -------------------------- + -----------------+
> |          gen space         |  max bot space   |


The space in which the bots should be generated is defined as "gen space". This means we can generate a random address in the range [0, 0x340) in which we can (in theory) place the first bot.

After placing the first bot at, for example, 0x40, the address space in which the address for the second bot is chosen from is shrunk to [0x40 + maxbotsize, 0x340] as displayed below.


> 0x000      0x040             0x340              0x400
> + ---------+---------------- + -----------------+
> | reserved |    gen space    |  max bot space   |


This might not work the first time, for example when using the default example of two bots in a memory space 1024 bytes big, each bot has (in theory) 512 bytes of memory to position itself in. Doing this for n bots in x bytes of memory results in n / x bytes per bot. This gets more problematic with a greater amount of bots in a limited memory space.

### Inserting bots into the arena

Inserting the bot into the arena is as easy as writing it's assembled code into the shared memory space. The command below writes the assembled bot to the memory location 0x100.


> [0x00000000]> wx e80000000058 @ 0x100

(2023-04-12: btw: you can also use the following command to write an assembled
file to the current offset):

> [0x00000000]> waf bot.asm

### Rounds

r2wars is a round based game. This means that we need to store the state of each "player" (bot) each round, so that the others can execute their operation. When it's the players turn again, the state has to be restored, so that the player can continue execution as if nothing had happened. r2 can dump all ESIL registers using the aer command and can even print a command to set the registers, aerR.


> [0x00000000]> aerR
> …
> aer eax = 0x00000000
> …
> aer esp = 0x00000000
> aer ebp = 0x00000000
> aer eip = 0x00000000
> …


By dumping these registers, we can easily restore the state of the bot, by replacing newline chars (\n) by semicolons (;) and executing the result with r2.

## Executing an instruction

After having created an "arena" and inserted a bot into the arena, we can execute an instruction, but before doing so, we still need to set up the"Progam Counter" (PC) and the "Stack Pointer" (SP) for the bot. We can do this by using the aer command, that can be used to manipulate the ESIL registers:


> [0x00000000]> aer PC = 0x100
> [0x00000000]> aer SP = SP + 0x100


After having done this, the VM is setup and the instruction pointer (Program Counter in ESIL slang) is pointing to the first instruction of our bot. In order to step into, we can use the aes command:


> [0x00000000]> aes


We haven't seen much of our bot yet, so let's look at what's happening. r2 can print the disassembly of the instructions at a specific offset using the pd command, so let's look at what is happening at the offset 0x100, that's where our bot is located.


> [0x00000105]> pd 0x4 @ 0x100
> 0x00000100  e800000000  call 0x105
> ;-- eip:
> 0x00000105  58        pop eax
> 0x00000106  0000      add byte [eax], al
> 0x00000108  0000      add byte [eax], al


What we've done above is we've printed the 0x4 instructions at the offset 0x100. As you can see, the instruction at 0x100 contains a call to 0x105, the pop eax instruction. Radare also displays the current location of the Instruction Pointer (eip) that is currently pointing to 0x105.

## Actually playing the "game"

Well, We're at the point at which you should have understood the basics, if not, DO NOT PANIC! You can read the "original" description <a href="https://github.com/radareorg/r2wars">here</a>.

If you have the desire to play around with this, you can clone my implementation from <a href="https://github.com/hanemile/r2wars">here</a>. It is ready to go with two example bots that you can adjust to your needs.

So from here on, you're on your own. Good luck.
