# collision

> Daddy told me about cool MD5 hash collision today.
> I wanna do something like that too!
> 
> ssh col@pwnable.kr -p2222 (pw:guest)


## What is given?

We get the binary col and the source it's compiled from col.c:


> #include <stdio.h>
> #include <string.h>
> unsigned long hashcode = 0x21DD09EC;
> unsigned long check_password(const char* p){
>     int* ip = (int*)p;
>     int i;
>     int res=0;
>     for(i=0; i<5; i++){
>         res += ip[i];
>     }
>     return res;
> }
> 
> int main(int argc, char* argv[]){
>     if(argc<2){
>         printf("usage : %s [passcode]\n", argv[0]);
>         return 0;
>     }
>     if(strlen(argv[1]) != 20){
>         printf("passcode length should be 20 bytes\n");
>         return 0;
>     }
> 
>     if(hashcode == check_password( argv[1] )){
>         system("/bin/cat flag");
>         return 0;
>     }
>     else
>         printf("wrong passcode.\n");
>     return 0;
> }


## Understanding the source

Let's go through this again line by line:


> #include <stdio.h>
> #include <string.h>


Some includes for libraries needed.


> unsigned long hashcode = 0x21DD09EC;


Some kind of variable, we don't know what it does at this point.


### check password function


> unsigned long check_password(const char* p){
>     int* ip = (int*)p;
>     int i;
>     int res=0;
>     for(i=0; i<5; i++){
>         res += ip[i];
>     }
>     return res;
> }


A "check_password" function, taking in a char* p (which is c slang for "String") returning some kind of result which seems to be an integer.

Let's look at this a bit closer:


> unsigned long check_password(const char* p){


This is the function signature, simply defining the name of the function (check_password), what arguments it expects (const char* p) and what it may return (unsigned long).


>   int* ip = (int*)p;


This takes the given string input and casts it to an array of pointers, with the first pointer being the given value.


>   int i;
>   int res=0;


Two variables are defined, i for specifying the index in the upcoming loop (more on that in the next block) and res is initialized as zero, we'll probably going to store the result of the operation here.


>   for(i=0; i<5; i++){
>       res += ip[i];
>   }


Now this is the actual operation, what happens here, is that for every pointer in the array of pointers (so every four bytes), the value get's added to the result. As the password consists of 20 chars, we add do this five times, once for each 4 byte block. For example, imagine you'd enter a password consisting of 20 * 'a': (AAAAAAAAAAAAAAAAAAAA). What happens is that the input is defined as an array of pointers with each entry being four bytes:


> [AAAA, AAAA, AAAA, AAAA, AAAA]


Each entry in this array is converted to it's hex representation:


> [0x41414141, 0x41414141, 0x41414141, 0x41414141, 0x41414141]


which as decimal results in:


> [1094795585, 1094795585, 1094795585, 1094795585, 1094795585]


Which when added together results in:


> 5473977925


>   return res;


And at last, we return the result.


### main function


Now, after looking at the password function, let's look at the main function:


> int main(int argc, char* argv[]){


The main function signature, nothing special, simply takes the argument count and an array of arguments.


>     if(argc<2){
>         printf("usage : %s [passcode]\n", argv[0]);
>         return 0;
>     }


This simply checks if the correct amount of arguments is given.


>     if(strlen(argv[1]) != 20){
>         printf("passcode length should be 20 bytes\n");
>         return 0;
>     }


The length of the password ist checked, it is supposed to be 40 chars long.


>     if(hashcode == check_password( argv[1] )){
>         system("/bin/cat flag");
>         return 0;
>     }


The hashcode (defined at the top (0x21DD09EC)) is used to check if the password is correct. This means that we need to enter a password so that the check_password function described above returns this value.


>     else
>         printf("wrong passcode.\n");
> 
>     return 0;
> }


## Exploiting

So, we need to generate an input that when added results in 0x21DD09EC == 568134124. We can try doing this as follows:

Divide the String by five:


> >>> 0x21DD09EC / 5
> 113626824.8


This doesn't result in an even value, which is bad, but we can try dividing it by five and finding that what is over using the % (modulo) operator:


> >>> 0x21DD09EC // 5
> 113626824
> >>> 0x21DD09EC % 5
> 4


With this knowledge, we know that we need four 113626824 blocks and one block that is 113626824 + 4 = 113626828.

We can check out calculation by adding them, reversing the process of generating the value:


> >>> hex((113626824 * 4) + 113626828)
> '0x21dd09ec'


This is correct! This means that what is left to do, is to convert the values to their hex representation and input them as the password:


> >>> hex(113626824)
> '0x6c5cec8'
> >>> hex(113626828)
> '0x6c5cecc'


Now inserting such hex values isn't really fun, but we can use python to help doing this. It is important to flip the bytes, and reverse the string direction, as this is stored using the little endian format, meaning the the least signigicant bits().


> >>> print("\xc8\xce\xc5\x06" * 4 + "\xcc\xce\xc5\x06")
> ����������


Using this, we can insert it into the first argument of the binary to get the result:


> col@pwnable:~$ ./col `python -c 'print("\xc8\xce\xc5\x06" * 4 + "\xcc\xce\xc5\x06")'`
> daddy! I just managed to create a hash collision :)


(Yes, I'm using python2 here, doing this with python3 is kind of weird)
