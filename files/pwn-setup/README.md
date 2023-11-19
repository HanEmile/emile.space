# pwn setup

My setup for solving pwn challenges in CTFs consists of a docker image that is handled using some aliases that are described further down.

- [Dockerfile](Dockerfile)
- [aliases.txt](aliases.txt)
- [aliases_fish.txt](aliases_fish.txt)


> docker build . -t ctf:ubuntu20.10


## Dockerfile


> FROM ubuntu:20.10
> 
> ENV DEBIAN_FRONTEND=noninteractive
> 
> RUN dpkg --add-architecture i386
> RUN apt update -y
> RUN apt upgrade -y
> 
> RUN apt install -y build-essential cmake curl dnsutils gcc gcc-multilib gdb gdb-multiarch git golang jq libc6:i386 libdb-dev libffi-dev libncurses5:i386 libpcre3-dev libssl-dev libstdc++6:i386 libxaw7-dev libxt-dev ltrace make netcat net-tools pkg-config procps python python3 python3-dev python3-pip radare2 rubygems sqlmap strace tmux upx vim wget
> 
> RUN pip install capstone requests r2pipe huepy
> RUN pip3 install pwntools keystone-engine unicorn capstone ropper angr
> 
> RUN r2pm update
> RUN mkdir tools && cd tools && \
> git clone https://github.com/JonathanSalwan/ROPgadget && \
> git clone https://github.com/radare/radare2 && cd radare2 && sys/install.sh && \
> cd .. && git clone https://github.com/pwndbg/pwndbg && cd pwndbg && ./setup.sh


## bash aliases

These are the bash alieses you can use to create the containers.


> # aliases.txt
> 
> alias pmk='function _dockermk(){docker run -v "$(pwd):/pwn" \
> --cap-add=SYS_PTRACE --security-opt seccomp=unconfined -d --name $1 -i \
> ctf:ubuntu20.10;};_dockermk'
> 
> alias pcd='function _dockercd(){docker exec -it --workdir /pwn $1 bash;};_dockercd'
> 
> alias prm='function _dockerrm(){docker stop $1;};_dockerrm'
> 
> alias pls='function _dockerls(){docker ps -a -f ancestor=ctf:ubuntu20.10 \
> --format "{{.Names}}";};_dockerls'


## fish functions

These are the fish aliases you can use to create the containers.


> # aliases_fish.txt
> 
> function pmk --argument name
>     docker run --rm -v (pwd)':/pwn' --cap-add=SYS_PTRACE --security-opt seccomp=unconfined -d --name $name -i ctf:ubuntu20.10
> end
> 
> function pcd --argument name
>     docker exec -it -e TERM=xterm-256color --workdir /pwn $name bash
> end
> 
> function prm --argument name
>     docker stop $name
> end
> 
> function pls
>     docker ps -a -f ancestor=ctf:ubuntu20.10 --format '{{.Names}}'
> end