patchelf --set-interpreter $(pwd)/ld-linux-x86-64.so.2 hof \
	&& patchelf --set-rpath $(pwd) hof
