# challenge: "flag_guesser"
NSJAIL_PORT=31333

# patch interpreter and libc
./patch.sh

cp hof /bin/hof

# run the challenge within nsjail
nsjail \
	-Ml \
	--port $NSJAIL_PORT \
	--chroot / \
	-E FLAG=flag{EA622CCC-437F-448D-8613-02013C978F41} \
	--user 1337 \
	--group 1337 \
	--stderr_to_null \
	-- /root/house_of_force/hof
