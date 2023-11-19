# flag

> Papa brought me a packed present! let's open it.
> 
> Download : http://pwnable.kr/bin/flag
> 
> This is reversing task. all you need is binary


## What is given?


We only get a binary.


## Understanding the source

There is no source, wait, there is! The binary itself. Altough the binary might not look like sourcecode (it really isn't), it contains instructions for our CPU to execute. Now we're only given this binary, so we'll have to do something with it...

Starting off, instead of directly jumping into some crazy tools, I like to get an overview of the binary by looking at the strings contained withing it. Yes, you read that right. For this, simply executing string -n 16 is enough to get some information that might give us some understanding on what we've got in front of us:


> root@a80be868eac7:/pwn# strings -n 16 flag | nl
>      1	'''' (0h''''HPX`
>      2	FFFF|vpjFFFFd^XR
>         
>         ...
> 
>     21	&9223372036854775807L`
>     22	PROT_EXEC|PROT_WRITE failed.
>     23	$Info: This file is packed with the UPX executable packer http://upx.sf.net $
>     24	$Id: UPX 3.08 Copyright (C) 1996-2011 the UPX Team. All Rights Reserved. $
>     25	GCC: (Ubuntu/Linaro 4.6.3-1u)#
>     26	DEH_FRAME_BEGINf
>     27	_PRETTY_FUNCT0Na


Now this might look pretty crazy, but there is information in there: The most important being the one in line 23: This file is packed with the UPX executable packer. For looking at the content of the binary, me must first unpack it using UPX, the Ultimate Packer for eXecutables:


> root@a80be868eac7:/pwn# upx -d flag
>                        Ultimate Packer for eXecutables
>                           Copyright (C) 1996 - 2020
> UPX 3.96        Markus Oberhumer, Laszlo Molnar & John Reiser   Jan 23rd 2020
> 
>         File size         Ratio      Format      Name
>    --------------------   ------   -----------   -----------
>     883745 <-    335288   37.94%   linux/amd64   flag
> 
> Unpacked 1 file.


Having unpacked the file, we can look around it it using [radare2](https://github.com/radareorg/radare2):


> root@a80be868eac7:/pwn# r2 flag
>  -- ==1337== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
> [0x00401058]>


Don't worry, the text after opening radare just displays some joke.

Now that you've got the binary open in radare, you've got to tell radare to analyze it. As radare is operated a lot through commands consisting of letter combinations, you'll probably find it weird. That's ok, that's totally normal and it'll stay that way for a while. In order to get familliar with commands, you can add the suffix ? and radare will present you with options. For example, as we want to analyze, we'll probably want to find out how radare can analyze. For this, we can use the following command and read the output:


> [0x00401058]> a?
> Usage: a  [abdefFghoprxstc] [...]
> | a                  alias for aai - analysis information
> | a*                 same as afl*;ah*;ax*
> | aa[?]              analyze all (fcns + bbs) (aa0 to avoid sub renaming)
> | a8 [hexpairs]      analyze bytes
> | ab[?]              analyze basic block
> | ac[?]              manage classes
> | aC[?]              analyze function call
> | aCe[?]             same as aC, but uses esil with abte to emulate the function
> | ad[?]              analyze data trampoline (wip)
> | ad [from] [to]     analyze data pointers to (from-to)
> | ae[?] [expr]       analyze opcode eval expression (see ao)
> | af[?]              analyze functions
> | aF                 same as above, but using anal.depth=1
> | ag[?] [options]    draw graphs in various formats
> | ah[?]              analysis hints (force opcode size, ...)
> | ai [addr]          address information (show perms, stack, heap, ...)
> | aj                 same as a* but in json (aflj)
> | aL                 list all asm/anal plugins (e asm.arch=?)
> | an [name] [@addr]  show/rename/create whatever flag/function is used at addr
> | ao[?] [len]        analyze Opcodes (or emulate it)
> | aO[?] [len]        Analyze N instructions in M bytes
> | ap                 find prelude for current offset
> | ar[?]              like 'dr' but for the esil vm. (registers)
> | as[?] [num]        analyze syscall using dbg.reg
> | av[?] [.]          show vtables
> | ax[?]              manage refs/xrefs (see also afx?)


Here, radare lists all possible commands that start with a. We'll want to get an understanding of the binary, or to be more precise, an understanding of what functions the binary consists of. For this, we can use the af command that will analyze the functions, so that we can use other commands to view information regarding them.

You can execute the af? command and look at the options that radare offers for analyzing functions. There's a lot, I'll use afr for analyzing the functions recursively. This should provide us with some information, or at least some information on what functions exist.

Now as the binary contains debug information, for example the name of the functions, radare can use this to our advantage. If you want to view the dissassembly of the main function, you can use the pd command (print dissassembly) using the sym.main argument:


> [0x00401058]> s sym.main
> [0x00401164]> pd
>             ;-- main:
>             0x00401164      55             push rbp
>             0x00401165      4889e5         mov rbp, rsp
>             0x00401168      4883ec10       sub rsp, 0x10
>             0x0040116c      bf58664900     mov edi, str.I_will_malloc___and_strcpy_the_flag_there._take_it. ; 0x496658 ; "I will malloc() and strcpy the flag there. take it."
>             0x00401171      e80a0f0000     call sym.puts
>             0x00401176      bf64000000     mov edi, 0x64               ; 'd' ; 100
>             0x0040117b      e850880000     call sym.malloc
>             0x00401180      488945f8       mov qword [rbp - 8], rax
>             0x00401184      488b15e50e2c.  mov rdx, qword [obj.flag]   ; [0x6c2070:8]=0x496628 str.UPX...__sounds_like_a_delivery_service_:_ ; "(fI"
>             0x0040118b      488b45f8       mov rax, qword [rbp - 8]
>             0x0040118f      4889d6         mov rsi, rdx
>             0x00401192      4889c7         mov rdi, rax
>             0x00401195      e886f1ffff     call 0x400320
>             0x0040119a      b800000000     mov eax, 0
>             0x0040119f      c9             leave
>             0x004011a0      c3             ret
>             0x004011a1      90             nop
>             0x004011a2      90             nop
>             0x004011a3      90             nop
>             0x004011a4      90             nop
>             0x004011a5      90             nop


Now radare prints a lot of information here, more than we'd actually like, but that's all right for now. For your understanding: the first column is the address of the instruction displayed, the second column the raw instruction and the third column contains the dissassembled instruction for us to read (reading the second column isn't really nice).

Reversing is mainly the art of starting from the bottom and working your way up, so known what to look out for is great. In radare, function calls are highlighted (it depends on how your terminal is setup, but the color of the call ... calls should be somehow different). Using these, you can get a quite nice understanding of what is happening, assuming that you've got names for the calls. In out case, we have! Let's go through the main function a few lines at a time, so you can get an understanding of what is happening:


>            ;-- main:


This is just a comment radare inserted for us to tell us: this is the "main" function. Useful, but not doing much...


>             0x00401164      55             push rbp
>             0x00401165      4889e5         mov rbp, rsp


Now this is a classic. When functions are called, a new stack frame is created. For this, information on the "old" parent frame needs to be stored somewhere. This is done like this: the old base pointer rbp is pushed onto the stack and the value of the old stack pointer is moved into the base pointer, "moving" it up, so that the base of the new frame lies above the top value of the last frame. (I'd recommend you to read the [x86 calling conventions](https://en.wikipedia.org/wiki/X86_calling_conventions) Wikipedia article and/or some blogposts on how function are called in assembler/c for understanding this topic, as it is really fundamental for everything to come).


>             0x00401168      4883ec10       sub rsp, 0x10


as soon as we've created the new stack frame, we'll subtract 0x10 from the frame pointer moving it "up". Now this might sound weird at first, but think about how the stack is located in memory, in which direction it "grows" and what the implications of this action is. If we're going to write some local arguments somewhere, we need somewhere to store them. With this operation, we've just made some space for this to happen.


>             0x0040116c      bf58664900     mov edi, str.I_will_malloc___and_strcpy_the_flag_there._take_it. ; 0x496658 ; "I will malloc() and strcpy the flag there. take it."
>             0x00401171      e80a0f0000     call sym.puts


And now, our first call. I've grouped this into two lines, as they belong together quite fundamentally. The first line moves the string I will malloc() and strcpy the flag there. take it. into the edi register (or to be more precise, a pointer to the string, as we can't fit the whole string into that small register). For understanding why this is insteresting and what happens next, you need to understand how function arguments are passed in 64-bit x86 assembler: The first 6 arguments are passed via registers (rdi, rsi, rdx, rcx, r9, r8 respectively), if there are more, they are pushed onto the stack. (Sidenote: in 32-bit x86 assembler, all arguments are pushed onto the stack). This means that in out case here, we insert the string into the rdi register that is the first argument used when a function is called. Looking into the next line, tada, a function is called!. The function sym.puts is called (the function is just called puts, the sym is inserted there by radare indicating that this information is taken from the symbols table). Reading the puts manpage (man puts) enlightens us on what puts does: it prints the first argument it gets to stdout.

And that's pretty much it! These two lines prepared a string to be prineted by inserting a pointer to it into the correct register and then called a function printing the string.

Let's go on...


>             0x00401176      bf64000000     mov edi, 0x64               ; 'd' ; 100
>             0x0040117b      e850880000     call sym.malloc


Same game: we're inserting the value 0x64 into the edi register (edi is just the lower 32 bits of the rdi register (e prefix = 32 bit, r prefix = 64 bit)). After inserting the value into the register, we can call the malloc function which will allocate some memory for us. In order to use this memory, we can use the return value that is stored in the rax register (just memorize this, put a post it on your screen or so).

Having called malloc, the string printed before spoilers a bit, but let's look at what's happening now...


>             0x00401180      488945f8       mov qword [rbp - 8], rax
>             0x00401184      488b15e50e2c.  mov rdx, qword [obj.flag]   ; [0x6c2070:8]=0x496628 str.UPX...__sounds_like_a_delivery_service_:_ ; "(fI"
>             0x0040118b      488b45f8       mov rax, qword [rbp - 8]


This looks quite weird at first, let's try to understand it (I've removed the long comment bellow):

- mov qword [rbp - 8], rax
  - this moves the value stored in rax (the pointer to the memory we've allocated before) into the value stored at [rbp - 8]. It might be interesting what exactly is here, but let's first look at what's happening next.
- mov rdx, qword [obj.flag]
  - the obj.flag quad word (qword) is moved into the rdx register. Now this is obviously our flag. We can print the value of this object in radare using the pf S @obj.flag command (I'd highly suggest you look at the output of the following commands: p?, pf?, pf??). This prints out the flag, so this challenge is actually done here, but for the sake of completeness, let's finish going through this function, as you might still learn something.
- mov rax, qword [rbp - 8]
  - Now this moves back the value temporarily stored at rbp - 8 into the rax register. Not really interesting, just the use of a local variable.

>             0x0040118f      4889d6         mov rsi, rdx
>             0x00401192      4889c7         mov rdi, rax
>             0x00401195      e886f1ffff     call 0x400320


We've got another function call here, as you can see. The arguments are populated using the values stored in the rdx and rax registers, but I'm not really in the mood for looking into this function, as we've already found the flag.


>             0x0040119a      b800000000     mov eax, 0
>             0x0040119f      c9             leave
>             0x004011a0      c3             ret


We're now getting to the end of the function. As when calling a function, when leaving a function, there are a few things that need to be done:

inserting a value into eax allows us to define a return value, as the caller will expect a value there indicating the return value
restoring the old stack frame (just lookup what leave and ret do)

>             0x004011a1      90             nop
>             0x004011a2      90             nop
>             ...


The rest if filled with nops. I don't know why, but it works.


## Exploiting

Well, no exploiting in this challenge, just reversing...