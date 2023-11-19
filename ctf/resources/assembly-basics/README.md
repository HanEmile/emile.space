# assembly basics

:::toc

## memory

### ram
  <!--<style>
      path {
        stroke: black;
      }
      @media (prefers-color-scheme: dark) {
        path { stroke: white; }
        text { fill: white; }
      }
  </style>-->

<!--</pre>
<svg
  width="100%" viewBox="-1 -1 60 40"
  style="border: 1px solid blue;">

  <path d="M 0 0 h 20 v 20 H 0 Z"
    fill="transparent"
    stroke-width="0.25"
    stroke-linecap="square">
    </path>

  <circle cx="0" cy="0" r="0.25" fill="red"/>
  <text
    x="0" y="0"
    dx="-1"
    font-size="1.75"
    dominant-baseline="middle"
    text-anchor="end">0x0000 0000 0000 0000</text>

  <circle cx="0" cy="20" r="0.25" fill="red"/>
  <text
    x="0" y="20"
    dx="-1"
    font-size="1.75"
    dominant-baseline="middle"
    text-anchor="end">0xffff ffff ffff ffff</text>
</svg>
<pre>-->

</pre>
<svg height="180px" width="100%" viewBox="0 0 9 15" preserveAspectRatio="none">
  <path
    d="M 0 14 L 1 15 L 2 10 L 3 11 L 4 7 L 5 5 L 6 0 L 7 5 L 8 10 L 9 11 L 9 15 L 0 15 Z"
    stroke="transparent"
    fill="pink"
  />
  <path
    d="M 0 14 L 1 15 L 2 10 L 3 11 L 4 7 L 5 5 L 6 0 L 7 5 L 8 10 L 9 11"
    stroke-width="2"
    stroke="red"
    fill="transparent"
    vector-effect="non-scaling-stroke"
  />
</svg>
<pre>


</pre>
<svg height="180px" width="100%" viewBox="0 0 200 200" preserveAspectRatio="none">
  <rect
    id="mem_0" x="10" y="1" width="40" height="40"
    fill="rgba(0,0,0,0)" class="box" pointer-events="all"
    stroke="black" vector-effect="non-scaling-stroke"/>
  <rect
    id="mem_1" x="10" y="41" width="40" height="40"
    fill="rgba(0,0,0,0)" class="box" pointer-events="all"
    stroke="black" vector-effect="non-scaling-stroke"/>
  <rect
    id="mem_2" x="10" y="81" width="40" height="40"
    fill="rgba(0,0,0,0)" class="box" pointer-events="all"
    stroke="black" vector-effect="non-scaling-stroke"/>
  </div>

  <text
    x="10" y="20"
    font-size="10px"
    dominant-baseline="middle"
    vector-effect="non-scaling-stroke"
    font-size-adjust="1.58">0xffff ffff ffff ffff</text>

  </g>
</svg>
<pre>

Memory can be addressed using some number:

> 0x00000000000000000000
> ...
> *memory*
> ...
> 0xffffffffffffffffffff

### binary

Somewhere in memory lies the binary:

> 0x??? .text
>       initialized data
>       .bss
>       heap
>        |
>        v
>       ...
> 
>       ...
>        ^
>        |
>       stack
>       cmd line args
> 0x???

### function frames

On the stack:

> ...

> locals          |
> base pointer    | line function
> ret addr        |
> parameters      |

> locals          |
> base pointer    | rectangle function
> ret addr        |
> parameters      |

## registers

### sizes

>   64 |                            32 |            16 |     8 |    0 |
>      v                               v               v       v      v
> rax: ................................................................
>                                eax:  ................................
>                                                  ax: ................
>                                                   ah ........        
>                                                           al ........

r?x: 64 bit
e?x: 32 bit
 ?x: 16 bit
 ?h: "high" 8 bit
 ?l: "low" 8 bit

### common x86 registers

- stack
  - rsp (stack pointer)
  - rbp (base pointer)

- function arguments
  - rdi
  - rsi
  - rdx
  - rcx

- return value
  - rax

- intruction pointer
  - rip

## stack

### push

> Stack: ___ ___ ___
> 
> push "a"
> 
> Stack: _a_ ___ ___
> 
> push "b"
> 
> Stack: _a_ _b_ ___
> 
> push "c"
> 
> Stack: _a_ _b_ _c_

### pop

> Stack: _a_ _b_ _c_
> rax: ___
> rbx: ___
> rcx: ___
> 
> pop "rax"
> 
> Stack: _a_ _b_ ___
> rax: _c_
> rbx: ___
> rcx: ___
> 
> pop "rbx"
> 
> Stack: _a_ ___ ___
> rax: _c_
> rbx: _b_
> rcx: ___
> 
> pop "rcx"
> 
> Stack: ___ ___ ___
> rax: _c_
> rbx: _b_
> rcx: _a_

## syntax

### intel

> mov rax, rbx

### AT&T

> mov %rax, %rbx

## Instruction

### mov

> mov dst, src

values in square brackets dereference pointers, so the following:

> mov rbx, [rax]

sould move the value the pointer that is stored in rax points to into rbx.

### sub / add

subtrace or add to the provided value

> sub rax, 0x100

> add rdx, [rax]

### ret

### leave

### call

### jmp

jne: jump if not equal
jnz: jump if not zero

## Functions

- group of instructions
- execute function by preparing registers, jumping to code, execution code and returning to original code
- function arguments passed depending on arch:
  - 32: stack
  - 64: registers (rdi, rsi, rdx, rcx, r8, r9)

### prolog

> push rip
> push rbp
> mov rbp, rsp

### epilog

> mov rsp, rbp
> pop rbp
> pop rip

## Buffer

> char str[16];

> _ _ _ _
> _ _ _ _
> _ _ _ _
> _ _ _ _ 

> ^
> | stack grows up
 
> | buffer get's written in the other dir
> v

> gets(str);

*input 16 "A"*

> A A A A
> A A A A
> A A A A
> A A A A
> _ _ _ _ <- old rbp
> _ _ _ _ <- old rip

*input 4 "B"*

> A A A A
> A A A A
> A A A A
> A A A A
> B B B B <- old rbp
> _ _ _ _ <- old rip

## Jump tables