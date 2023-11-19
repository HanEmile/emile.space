# fd

> Mommy! what is a file descriptor in Linux?
> 
> * try to play the wargame your self but if you are ABSOLUTE beginner, follow this tutorial link:
> https://youtu.be/971eZhMHQQw
> 
> ssh fd@pwnable.kr -p2222 (pw:guest)

## What is given?

We get a file called fd.c, the corresponding binary fd and a flag flag.

As we get the sourcecode, let's inspect it:


> fd@pwnable:~$ cat fd.c
> #include <stdio.h>
> #include <stdlib.h>
> #include <string.h>
> char buf[32];
> int main(int argc, char* argv[], char* envp[]){
>     if(argc<2){
>         printf("pass argv[1] a number\n");
>         return 0;
>     }
>     int fd = atoi( argv[1] ) - 0x1234;
>     int len = 0;
>     len = read(fd, buf, 32);
>     if(!strcmp("LETMEWIN\n", buf)){
>         printf("good job :)\n");
>         system("/bin/cat flag");
>         exit(0);
>     }
>     printf("learn about Linux file IO\n");
>     return 0;
> 
> }


## Understanding the source

Let's look at the file line by line:


> #include <stdio.h>
> #include <stdlib.h>
> #include <string.h>


Just some imports, nothing really interesting.


> char buf[32];


A chat buffer get's defined, we will probably write stuff into here...


> int main(int argc, char* argv[], char* envp[]){
>     if(argc<2){
>         printf("pass argv[1] a number\n");
>         return 0;
>     }


This is the definition of the main function with some code checking if the right amount of arguments was supplied... still not really interesting.


>     int fd = atoi( argv[1] ) - 0x1234;


Now this get's interesting: The first command line argument (argv[1]) is passed to atoi (execute man atoi for more information on atoi). In a nutshell, atoi converts out input to an integer (Ascii TO Integer) and then subtracts 0x1234 from it. This means that we can controll the content of the fd variable: If we want to insert a value n into the var, we insert n + 0x1234.


>     int len = 0;


Some var len is initialized as 0, nothing we can do here.


>     len = read(fd, buf, 32);


Now here, the read function is used to "read from a file descriptor" (read the manpage `man 2 read` for more info on the read function).

Looking into the manpage, the read functions signature is the following:


> ssize_t read(int fd, void *buf, size_t count);


From the manpage:

"[...] read() attempts to read up to count bytes from file descriptor fd into the buffer starting at buf."

This means that the the address of the buffer defined in the beginning ist passed in, some file descriptor that should be read from (remember, we controll the number of that file descriptor) and the amount of bytes to read in (in this case 32).

As we control the file descriptor, we can read 32 bytes of data from an arbitrary file descriptor into the buffer.


>     if(!strcmp("LETMEWIN\n", buf)){
>         printf("good job :)\n");
>         system("/bin/cat flag");
>         exit(0);
>     }


This checks if the content of the buffer is LETMEWIN. If so, it prints the content of the flag file and exists...


>     printf("learn about Linux file IO\n");
>     return 0;
> 
> }


...but if not, It tells us to learn about Linux file IO.


## Solving the challenge

Now that you've got a basic understanding of the binary, it shouldn't be to hard to find out how to solve this. In the end, we need to get the String LETMEWIN into the buffer and the only thing we can controll is the input and the file descriptor from where the content is copied into the buffer.

The "most common" file descriptors are 0, 1 and 2. You might want to read the [wikipedia page on file descriptors](https://en.wikipedia.org/wiki/File_descriptor) in order to get a basic understanding of what this actually all means.

On a very basic level, 0 is the Standard Input. If we read from here, we get the content the user inserts into their commandline. 1 is the Standard output. If we write data here, we can print stuff to the commandline. And at last, 2 is the standard error, works the same as the standard output, but offers an alternative stream allowing to separate the actual content for error content, allowing the user to, for example, filter out the errors and watch only the actual content.

Now that we can control the file pointer, we probably want to use the file descriptor 0 as the input, as this allows us to write content to the command line that is then passed into the buffer.

In order to get the fd value to 0, we need to insert 0 + 0x1234 which is:


> >>> 0 + 0x1234
> 4660


With this information we can get the flag like this:


> fd@pwnable:~$ ./fd 4660
> LETMEWIN
> good job :)
> mommy! I think I know what a file descriptor is!!