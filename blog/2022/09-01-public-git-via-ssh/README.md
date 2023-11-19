# public git via ssh

> mkdir git

## setup /dev

> mkdir dev
> cd dev
> mknod -m 666 null c 1 3
> mknod -m 666 tty c 5 0
> mknod -m 666 zero c 1 5
> mknod -m 666 random c 1 8

## setup permissions

> chown root:root git
> chown 0755 git

## setup a shell

> cd git
> mkdir bin
> cp /bin/bash .

identify libs:

> ldd /bin/bash

create libs folder

> cd ..
> mkdir -p lib/x86_64-linux-gnu/
> mkdir lib64

copy libs to folder

> cp ... ...

## create ssh user

> useradd git

> mkdir etc
> cp /etc/passwd etc
> cp /etc/group etc

> cat << EOF
> Match User git
> ChrootDirectory /var/www/git
> EOF >> /etc/ssh/sshd_config

> systemctl restart sshd
