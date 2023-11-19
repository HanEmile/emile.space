# know_your_mem

:::toc

[https://archive.ooo/c/know_your_mem/359/](https://archive.ooo/c/know_your_mem/359/)


## Given files

- [Makefile](#makefile)
- [README.md](#readmemd)
- [know_your_mem.c](#knowyourmemc)
- [shellcode.c](#shellcodec)
- [simplified.c](#simplifiedc)
- [simplified_shellcode.so.c](#simplifiedshellcodesoc)
- [topkt.py](#topktpy)

Let's go through the file and see what we've got

### Makefile

> # sudo apt-get install libseccomp-dev libseccomp2
> 
> CFLAGS ?= -Wall
> 
> # 64 bit!
> CFLAGS += -m64 -std=gnu99
> 
> # Just making sure
> HARDENING_FLAGS += -pie -fPIE -Wl,-z,relro -Wl,-z,now -fstack-protector-all -D_FORTIFY_SOURCE=2 -Wformat=2 -Werror=format-security
> 
> 
> all: know_your_mem simplified
> 
> 
> know_your_mem: LDLIBS += -lseccomp
> know_your_mem: CFLAGS += -O3 -march=native -s $(HARDENING_FLAGS)
> 
> simplified: LDLIBS += -lseccomp -ldl
> simplified: CFLAGS += -DSIMPLIFIED -g3 -ggdb $(HARDENING_FLAGS)
> 
> 
> %.so: CFLAGS += -shared -fPIC
> %.so: LDFLAGS += -shared -fPIC
> 
> 
> check: all flag simplified_shellcode.so shellcode.bin.pkt
>         ./simplified
>         @echo "Good, the simplified version worked! Let's now try raw shellcode..."
>         ./know_your_mem < shellcode.bin.pkt | tee | fgrep --text 'OOO{theflagwillbehere}'
>         @echo "Perfect! Now go get that flag :)"
> 
> 
> mycheck: all flag solution.so solution.bin.pkt
>         ./simplified ./solution.so
>         ./know_your_mem < solution.bin.pkt | tee | fgrep --text 'OOO{theflagwillbehere}'
>         @echo "Good, my solution worked :)"
> 
> 
> %.bin: %.c
>         gcc -nostdlib -static -fPIC -Os -Wall -DNDEBUG -fno-exceptions -fno-asynchronous-unwind-tables -fno-unwind-tables -s -o $*.elf $<
>         !(readelf -W --sections $*.elf | egrep '\.(ro)?data') || echo -e "\n\nWARNING: you have .(ro)data, you'll have to adjust this build.\n\n" >/dev/stderr
>         objcopy $*.elf --dump-section .text=$@
> 
> %.bin.pkt: %.bin
>         ./topkt.py $<
> 
> 
> flag:
>         @echo 'Creating a fake flag for testing convenience'
>         @echo 'OOO{theflagwillbehere} Make sure you print it to stdout, stderr may go to /dev/null in the hosted version.' > flag
> 
> .PHONY: clean all check mycheck
> clean:
>         rm -f simplified know_your_mem shellcode.bin shellcode.bin.pkt solution.bin solution.bin.pkt checks/*.pkt checks/*.elf *.elf *.so

### README.md

> In this challenge, `know_your_mem.c` is the meat.
> 
> However, remember that timeouts are strict -- it's suggested to first try locally in C.
> 
> Basically:
> 
>   # First solve it in 'standard' C without triggering alarm()
>   sudo apt install libseccomp-dev libseccomp2
>   edit simplified_shellcode.so.c
>   make check
> 
>   # Switch syscalls to Google's linux_syscall_support
>   edit shellcode.c
>   make check
> 
>   # If all goes well, shellcode.bin.pkt will be ready to submit as-is!

### know_your_mem.c

> #define _GNU_SOURCE
> #include <sys/mman.h>
> #include <sys/stat.h>
> #include <sys/random.h>
> #include <sys/resource.h>
> #include <sys/time.h>
> #include <sys/types.h>
> #include <sys/utsname.h>
> #include <dlfcn.h>
> #include <err.h>
> #include <errno.h>
> #include <error.h>
> #include <inttypes.h>
> #include <fcntl.h>
> #include <signal.h>
> #include <stdio.h>
> #include <stdlib.h>
> #include <string.h>
> #include <seccomp.h>
> #include <time.h>
> #include <unistd.h>
> 
> typedef void* (*shellcodefn)();
> 
> #ifdef SIMPLIFIED
> # define hint(x, ...) fprintf(stderr, "[H] " x, __VA_ARGS__)
> #else
> # define hint(x, ...)
> #endif
> 
> 
> #define ADDR_MIN   0x0000100000000000UL  // Low-ish
> #define ADDR_MASK  0x00000ffffffff000UL  // Page-aligns
> #define N_FAKES   30
> #define HEADER    "OOO: You found it, congrats! The flag is: "
> 
> static void *random_addr()
> {
>     uintptr_t ret;
>     //int fd = open("/dev/urandom", O_RDONLY); if (read(fd, &ret, sizeof(ret)) != sizeof(ret)) { err(47, "urandom"); } close(fd);
>     if (getrandom(&ret, sizeof(ret), GRND_NONBLOCK) != sizeof(ret)) err(47, "getrandom");
>     return (void*)((ret & ADDR_MASK) + ADDR_MIN);
> }
> 
> static void *map_page(void *addr)
> {
>     void *ret = mmap(addr, 4096,
>             PROT_READ|PROT_WRITE,
>             MAP_ANONYMOUS|MAP_PRIVATE | (addr != NULL ? MAP_FIXED : 0),
>             -1, 0);
> #ifdef SIMPLIFIED
>     if (ret == MAP_FAILED)
>         err(8, "Could not mmap() at %p -- maybe I was not lucky with random picking?", addr);
>     if (addr != NULL && ret != addr)
>         err(99, "Wrong flags to mmap? ret = %p != %p = wanted", ret, addr);
> #endif
>     return ret;
> }
> 
> 
> static void* put_secret_somewhere_in_memory()
> {
>     fprintf(stderr, "[ ] Putting the flag somewhere in memory...\n");
> 
>     char *pg = map_page(random_addr());
> 
>     strcpy(pg, HEADER);
>     int fd = TEMP_FAILURE_RETRY(open("flag", O_RDONLY));
>     if (fd == -1)
>         err(37, "open ./flag");
>     struct stat st;
>     if (fstat(fd, &st) != 0)
>         err(38, "flag fstat");
>     ssize_t flag_read = TEMP_FAILURE_RETRY(read(fd, pg + strlen(HEADER), st.st_size));
>     if (flag_read != st.st_size)
>         err(39, "flag read");
>     printf("Secret loaded (header + %zd bytes)\n", flag_read);
>     close(fd);
>     if (mprotect(pg, 4096, PROT_READ) != 0)
>         err(40, "mprotect");
> 
>     hint("The flag is at %p\n", pg);
>     return pg;
> }
> 
> 
> static void put_fakes_in_memory()
> {
>     fprintf(stderr, "[ ] Putting red herrings in memory...\n");
>     for (int i = 0; i < N_FAKES; i++) {
>         char *pg = map_page(random_addr());
>         strcpy(pg, "Sorry, this is just a red herring page. Keep looking!");
>         hint("Red herring at %p\n", pg);
>     }
> }
> 
> 
> static void filter_syscalls()
> {
>     int ret;
> #ifdef SIMPLIFIED
>     scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_TRAP);
> #else
>     scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_KILL);
> #endif
>     if (ctx == NULL)
>         err(5, "seccomp_init");
> 
>     ret  = seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit_group), 0);
> 
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(write), 0);
>     
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(munmap), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mprotect), 0);
> 
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(brk), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(set_thread_area), 0);
> #ifdef SIMPLIFIED
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(sigreturn), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(rt_sigreturn), 0);
> #endif
> 
>     if (ret < 0)
>         error(6, -ret, "allow rules");
>     ret = seccomp_load(ctx);
>     if (ret < 0)
>         error(6, -ret, "seccomp_load");
>     fprintf(stderr, "[*] seccomp filter now active!\n");
>     seccomp_release(ctx);
> }
> 
> #ifdef SIMPLIFIED
> static int got_alarm = 0;
> static void time_warning(int sig)
> {
>     got_alarm = 1;
>     fprintf(stderr, "[!] You're taking too long! I'll let you continue for now.\n");
> }
> static shellcodefn load_shellcode(const char *filename)
> {
>     printf("Loading your simplified solution from %s\n", filename);
>     void *d = dlopen(filename, RTLD_NOW);
>     if (d == NULL)
>         errx(7, "Couldn't load the .so, did you build it? Try 'make check'.\n\tdlopen error: %s", dlerror());
>     void *ret = dlsym(d, "shellcode");
>     if (ret == NULL)
>         errx(7, "Couldn't find the 'shellcode' symbol. Should be a global function: %s", dlerror());
>     return ret;
> }
> #else
> static shellcodefn load_shellcode()
> {
>     printf("Send the length (uint16), then the shellcode.\n");
>     uint16_t len;
>     if (fread(&len, 1, 2, stdin) != 2)
>         err(30, "len?");
>     if (len > 10*4096)
>         errx(31, "Too long! Max shellcode size is 10K");
>     unsigned char *shellcode = mmap((void*) 0x40000000, 10*4096, PROT_READ|PROT_WRITE, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
>     if (shellcode == MAP_FAILED)
>         err(33, "failed to mmap pages for your shellcode");
>     if (fread(shellcode, 1, len, stdin) != len)
>         err(32, "fread error: shellcode len?");
>     printf("[ ] All right, I read %" PRIu16 " bytes. I will call the first byte in a bit.\n", len);
>     if (mprotect(shellcode, 4096, PROT_READ|PROT_EXEC) != 0)
>         err(89, "mprotect shellcode");
>     return (shellcodefn) shellcode;
> }
> #endif
> 
> 
> int main(int argc, char *argv[])
> {
> #ifdef SIMPLIFIED
>     signal(SIGALRM, time_warning);
> #endif
>     alarm(10);
>     setbuf(stdin, NULL);
>     setbuf(stdout, NULL);
>     //srand(time(NULL));
>     struct rlimit as_limit = {  // Yes, the live version also has CPU limits
>         .rlim_cur = 100 * 1024 * 1024,
>         .rlim_max = 110 * 1024 * 1024
>     };
>     if (setrlimit(RLIMIT_AS, &as_limit) != 0)
>         warn("RLIMIT_AS");
> 
> 
>     struct utsname un;
>     uname(&un);
>     printf("[ ] This challenge may be slightly easier in Linux 4.17+. "
>             "Here, we're running on %s %s (%s)\n",
>             un.sysname, un.release, un.machine);
> 
> 
> #ifdef SIMPLIFIED
>     shellcodefn shellcode = load_shellcode((argc >= 2) ? argv[1] : "./simplified_shellcode.so");
>     //system("cat /proc/$PPID/maps");
> #else
>     shellcodefn shellcode = load_shellcode();
> #endif
> 
> 
> #ifdef SIMPLIFIED
>     void *secret_addr =
> #endif
>         put_secret_somewhere_in_memory();
>     put_fakes_in_memory();
> 
> 
>     fflush(NULL);
>     filter_syscalls();
>     void *found = shellcode();
>     fprintf(stderr, "[*] Your shellcode returned %p\n", found);
> 
> #ifdef SIMPLIFIED
>     if (got_alarm)
>         fprintf(stderr, "[W] Your solution took too long! Try adjusting it a bit. It should comfortably fit in the time limit.\n");
>     if (secret_addr == found) {
>         fprintf(stderr, "[^] Success! Make sure you're also printing the flag, and that it's not taking too long. Next: convert your solution to raw shellcode -- you can start with C code, BTW! shellcode.c shows one way to do it.\n");
>         return 0;
>     } else {
>         fprintf(stderr, "[!] Sorry, you didn't find the secret address.\n");
>         return 1;
>     }
> #endif
> }

### shellcode.c

> // This is an example of turning simple C into raw shellcode.
> 
> // make shellcode.bin will compile to assembly
> // make shellcode.bin.pkt will prepend the length so you can
> //    ./know_your_mem < shellcode.bin.pkt
> 
> // Note: Right now the 'build' does not support .(ro)data
> //       If you want them you'll have to adjust the Makefile.
> //       They're not really necessary to solve this challenge though.
> 
> 
> // From https://chromium.googlesource.com/linux-syscall-support/
> static int my_errno = 0;
> #define SYS_ERRNO my_errno
> #include "linux-syscall-support/linux_syscall_support.h"
> 
> 
> #define ADDR_MIN   0x0000100000000000UL
> #define ADDR_MASK  0x00000ffffffff000UL
> 
> 
> void _start()
> {
>     sys_write(1, __builtin_frame_address(0), 5);  // Prints something (note: best avoid literals)
>     sys_exit_group(2);                            // Exit
> }

### simplified.c

> #define _GNU_SOURCE
> #include <sys/mman.h>
> #include <sys/stat.h>
> #include <sys/random.h>
> #include <sys/resource.h>
> #include <sys/time.h>
> #include <sys/types.h>
> #include <sys/utsname.h>
> #include <dlfcn.h>
> #include <err.h>
> #include <errno.h>
> #include <error.h>
> #include <inttypes.h>
> #include <fcntl.h>
> #include <signal.h>
> #include <stdio.h>
> #include <stdlib.h>
> #include <string.h>
> #include <seccomp.h>
> #include <time.h>
> #include <unistd.h>
> 
> typedef void* (*shellcodefn)();
> 
> #ifdef SIMPLIFIED
> # define hint(x, ...) fprintf(stderr, "[H] " x, __VA_ARGS__)
> #else
> # define hint(x, ...)
> #endif
> 
> 
> #define ADDR_MIN   0x0000100000000000UL  // Low-ish
> #define ADDR_MASK  0x00000ffffffff000UL  // Page-aligns
> #define N_FAKES   30
> #define HEADER    "OOO: You found it, congrats! The flag is: "
> 
> static void *random_addr()
> {
>     uintptr_t ret;
>     //int fd = open("/dev/urandom", O_RDONLY); if (read(fd, &ret, sizeof(ret)) != sizeof(ret)) { err(47, "urandom"); } close(fd);
>     if (getrandom(&ret, sizeof(ret), GRND_NONBLOCK) != sizeof(ret)) err(47, "getrandom");
>     return (void*)((ret & ADDR_MASK) + ADDR_MIN);
> }
> 
> static void *map_page(void *addr)
> {
>     void *ret = mmap(addr, 4096,
>             PROT_READ|PROT_WRITE,
>             MAP_ANONYMOUS|MAP_PRIVATE | (addr != NULL ? MAP_FIXED : 0),
>             -1, 0);
> #ifdef SIMPLIFIED
>     if (ret == MAP_FAILED)
>         err(8, "Could not mmap() at %p -- maybe I was not lucky with random picking?", addr);
>     if (addr != NULL && ret != addr)
>         err(99, "Wrong flags to mmap? ret = %p != %p = wanted", ret, addr);
> #endif
>     return ret;
> }
> 
> 
> static void* put_secret_somewhere_in_memory()
> {
>     fprintf(stderr, "[ ] Putting the flag somewhere in memory...\n");
> 
>     char *pg = map_page(random_addr());
> 
>     strcpy(pg, HEADER);
>     int fd = TEMP_FAILURE_RETRY(open("flag", O_RDONLY));
>     if (fd == -1)
>         err(37, "open ./flag");
>     struct stat st;
>     if (fstat(fd, &st) != 0)
>         err(38, "flag fstat");
>     ssize_t flag_read = TEMP_FAILURE_RETRY(read(fd, pg + strlen(HEADER), st.st_size));
>     if (flag_read != st.st_size)
>         err(39, "flag read");
>     printf("Secret loaded (header + %zd bytes)\n", flag_read);
>     close(fd);
>     if (mprotect(pg, 4096, PROT_READ) != 0)
>         err(40, "mprotect");
> 
>     hint("The flag is at %p\n", pg);
>     return pg;
> }
> 
> 
> static void put_fakes_in_memory()
> {
>     fprintf(stderr, "[ ] Putting red herrings in memory...\n");
>     for (int i = 0; i < N_FAKES; i++) {
>         char *pg = map_page(random_addr());
>         strcpy(pg, "Sorry, this is just a red herring page. Keep looking!");
>         hint("Red herring at %p\n", pg);
>     }
> }
> 
> 
> static void filter_syscalls()
> {
>     int ret;
> #ifdef SIMPLIFIED
>     scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_TRAP);
> #else
>     scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_KILL);
> #endif
>     if (ctx == NULL)
>         err(5, "seccomp_init");
> 
>     ret  = seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit_group), 0);
> 
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(write), 0);
>     
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(munmap), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(mprotect), 0);
> 
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(brk), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(set_thread_area), 0);
> #ifdef SIMPLIFIED
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(sigreturn), 0);
>     ret |= seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(rt_sigreturn), 0);
> #endif
> 
>     if (ret < 0)
>         error(6, -ret, "allow rules");
>     ret = seccomp_load(ctx);
>     if (ret < 0)
>         error(6, -ret, "seccomp_load");
>     fprintf(stderr, "[*] seccomp filter now active!\n");
>     seccomp_release(ctx);
> }
> 
> #ifdef SIMPLIFIED
> static int got_alarm = 0;
> static void time_warning(int sig)
> {
>     got_alarm = 1;
>     fprintf(stderr, "[!] You're taking too long! I'll let you continue for now.\n");
> }
> static shellcodefn load_shellcode(const char *filename)
> {
>     printf("Loading your simplified solution from %s\n", filename);
>     void *d = dlopen(filename, RTLD_NOW);
>     if (d == NULL)
>         errx(7, "Couldn't load the .so, did you build it? Try 'make check'.\n\tdlopen error: %s", dlerror());
>     void *ret = dlsym(d, "shellcode");
>     if (ret == NULL)
>         errx(7, "Couldn't find the 'shellcode' symbol. Should be a global function: %s", dlerror());
>     return ret;
> }
> #else
> static shellcodefn load_shellcode()
> {
>     printf("Send the length (uint16), then the shellcode.\n");
>     uint16_t len;
>     if (fread(&len, 1, 2, stdin) != 2)
>         err(30, "len?");
>     if (len > 10*4096)
>         errx(31, "Too long! Max shellcode size is 10K");
>     unsigned char *shellcode = mmap((void*) 0x40000000, 10*4096, PROT_READ|PROT_WRITE, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
>     if (shellcode == MAP_FAILED)
>         err(33, "failed to mmap pages for your shellcode");
>     if (fread(shellcode, 1, len, stdin) != len)
>         err(32, "fread error: shellcode len?");
>     printf("[ ] All right, I read %" PRIu16 " bytes. I will call the first byte in a bit.\n", len);
>     if (mprotect(shellcode, 4096, PROT_READ|PROT_EXEC) != 0)
>         err(89, "mprotect shellcode");
>     return (shellcodefn) shellcode;
> }
> #endif
> 
> 
> int main(int argc, char *argv[])
> {
> #ifdef SIMPLIFIED
>     signal(SIGALRM, time_warning);
> #endif
>     alarm(10);
>     setbuf(stdin, NULL);
>     setbuf(stdout, NULL);
>     //srand(time(NULL));
>     struct rlimit as_limit = {  // Yes, the live version also has CPU limits
>         .rlim_cur = 100 * 1024 * 1024,
>         .rlim_max = 110 * 1024 * 1024
>     };
>     if (setrlimit(RLIMIT_AS, &as_limit) != 0)
>         warn("RLIMIT_AS");
> 
> 
>     struct utsname un;
>     uname(&un);
>     printf("[ ] This challenge may be slightly easier in Linux 4.17+. "
>             "Here, we're running on %s %s (%s)\n",
>             un.sysname, un.release, un.machine);
> 
> 
> #ifdef SIMPLIFIED
>     shellcodefn shellcode = load_shellcode((argc >= 2) ? argv[1] : "./simplified_shellcode.so");
>     //system("cat /proc/$PPID/maps");
> #else
>     shellcodefn shellcode = load_shellcode();
> #endif
> 
> 
> #ifdef SIMPLIFIED
>     void *secret_addr =
> #endif
>         put_secret_somewhere_in_memory();
>     put_fakes_in_memory();
> 
> 
>     fflush(NULL);
>     filter_syscalls();
>     void *found = shellcode();
>     fprintf(stderr, "[*] Your shellcode returned %p\n", found);
> 
> #ifdef SIMPLIFIED
>     if (got_alarm)
>         fprintf(stderr, "[W] Your solution took too long! Try adjusting it a bit. It should comfortably fit in the time limit.\n");
>     if (secret_addr == found) {
>         fprintf(stderr, "[^] Success! Make sure you're also printing the flag, and that it's not taking too long. Next: convert your solution to raw shellcode -- you can start with C code, BTW! shellcode.c shows one way to do it.\n");
>         return 0;
>     } else {
>         fprintf(stderr, "[!] Sorry, you didn't find the secret address.\n");
>         return 1;
>     }
> #endif
> }

### simplified_shellcode.so.c

> #include <stdio.h>
> #include <unistd.h>
> 
> #define ADDR_MIN   0x0000100000000000UL
> #define ADDR_MASK  0x00000ffffffff000UL
> 
> 
> void *shellcode()
> {
>     // 1. Find the secret in memory (starts with "OOO:")
>     // 2. Print it
>     // 3. ...
>     // 4. PROFIT!
> 
>     printf("Hi! Soon I'll be your shellcode!\n");
> 
>     return (void*) 0x123456; // For this simplified test it's also OK to return the address
> }

### topkt.py

> #!/usr/bin/env python3
> 
> """Turn a raw shellcode binary into the format expected by know_your_mem."""
> 
> import os, sys, struct
> 
> with open(sys.argv[1], "rb") as inf, open(sys.argv[1]+".pkt", "wb") as outf:
>     l = os.fstat(inf.fileno()).st_size
>     outf.write(struct.pack("<H", l))        # uint16 length
>     outf.write(inf.read(l))                 # payload
> 
> assert os.stat(sys.argv[1]+".pkt").st_size == 2+l
