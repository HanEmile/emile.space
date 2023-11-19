# symbolic execution

## old python2 syntax

> import os
> import angr
> 
> project = angr.Project("binaryname", auto_load_libs=False)
> path_group = project.factory.path_group()
> 
> //path_group.explore(find=0x400000)
> path_group.explore(find=lambda path: "Nice!" in path.state.posix.dumps(1))
> 
> print path_group.found[0].state.posix.dumps(0)

## tooling

### r4ge (angr for r2)

- view arg s using `.(args)`
- mark memory as symbolic using `.(markMemSymbolic address bytes name)`
- insert flags for finding/avoiding (go to Visual mode (`Vp`) and add flags using `f`)
  - `r4ge.avoidn` (n) represents the n'th avoid addr, as r2 can't work with multiple flags with the same name
  - `r4ge.find`
- `.(rage)`