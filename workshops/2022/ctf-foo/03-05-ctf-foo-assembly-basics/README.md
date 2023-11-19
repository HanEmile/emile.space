# assembly basics

[emile](/about#contact) [/ctf/resources/assembly-basics/](/ctf/resources/assembly-basics/)

This workshop is there to build a solid foundation for all further workshops. We'll go over the following topics

- Memory
- Registers
- Stack
- Instruction
- Function Calls
  - prolog / epilogue
- Buffer
- Jump tables
- From C to x86, the complete process

## What we actually did

We took a binary with a given leak, showed how to calculate the libc base using that leak and how to find a place to jump in the binary to get a shell using a one-shot-gadget.