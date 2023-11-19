FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386

RUN apt update
#RUN apt upgrade

RUN apt install -y build-essential cmake curl dnsutils gcc gcc-multilib gdb gdb-multiarch git golang jq libc6:i386 libdb-dev libffi-dev libncurses5:i386 libpcre3-dev libssl-dev libstdc++6:i386 libxaw7-dev libxt-dev ltrace make netcat net-tools pkg-config procps python python3 python3-dev python3-pip radare2 rubygems sqlmap strace tmux upx vim wget

RUN pip install capstone requests r2pipe huepy
RUN pip3 install pwntools keystone-engine unicorn capstone ropper angr

RUN r2pm update
RUN mkdir tools && cd tools && \
git clone https://github.com/JonathanSalwan/ROPgadget && \
git clone https://github.com/radare/radare2 && cd radare2 && sys/install.sh && \
cd .. && git clone https://github.com/pwndbg/pwndbg && cd pwndbg && ./setup.sh
