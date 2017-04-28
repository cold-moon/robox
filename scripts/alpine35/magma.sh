#!/bin/bash -eux

# The packages needed to compile magma.
apk add --force bash m4 gcc g++ gdb gdbm grep perl make glib expat musl musl-utils \
automake autoconf valgrind binutils binutils-libs gmp isl mpc1 python2 pkgconf \
mpfr3 libtool flex bison cmake ca-certificates patch ncurses-doc ncurses-libs \
ncurses-dev ncurses-static ncurses ncurses-terminfo-base ncurses-terminfo \
util-linux-dev makedepend linux-vanilla-dev build-base coreutils ctags \
diffutils doxygen elfutils fortify-headers gawk sed texinfo bsd-compat-headers \
libc-utils patchutils strace tar \
libbz2 libgomp libatomic libltdl libbsd libattr libacl libarchive libcurl \
libpthread-stubs libgcc libgc++ libc6-compat \
glib-dev libc-dev musl-dev valgrind-dev libbsd-dev subunit-dev  marco-dev \
acl-dev popt-dev python2-dev pkgconf-dev zlib-dev \
gcc-doc m4-doc make-doc patch-doc

# libbsd-dev libsubunit-dev libsubunit0 pkg-config

# Need to retrieve the source code.
apk add --force git git-doc git-perl popt rsync wget

# Needed to run the watcher and status scripts.
apk add --force sysstat inotify-tools lm_sensors sysfsutils

# Needed to run the stacie script.
apk add --force py2-crypto py2-cryptography py2-cparser py2-cffi py2-idna py2-asn1 py2-six py2-ipaddress

# Setup the the box. This runs as root
if [ -d /home/vagrant/ ]; then
  OUTPUT="/home/vagrant/magma-build.sh"
else
  OUTPUT="/root/magma-build.sh"
fi

# Grab a snapshot of the development branch.
cat <<-EOF > $OUTPUT
#!/bin/bash

error() {
  if [ \$? -ne 0 ]; then
    printf "\n\nmagma daemon compilation failed...\n\n";
    exit 1
  fi
}

if [ -x /usr/bin/id ]; then
  ID=\`/usr/bin/id -u\`
  if [ -n "\$ID" -a "\$ID" -eq 0 ]; then
    systemctl start mariadb.service
    systemctl start postfix.service
    systemctl start memcached.service
  fi
fi

# Temporary [hopefully] workaround to avoid [yet another] bug in NSS.
export NSS_DISABLE_HW_AES=1

# Clone the magma repository off Github.
git clone https://github.com/lavabit/magma.git magma-develop; error
cd magma-develop; error

# Compile the dependencies into a shared library.
dev/scripts/builders/build.lib.sh all; error

# Reset the sandbox database and storage files.
dev/scripts/database/schema.reset.sh; error

# Enable the anti-virus engine and update the signatures.
dev/scripts/freshen/freshen.clamav.sh 2>&1 | grep -v WARNING | grep -v PANIC; error
sed -i -e "s/virus.available = false/virus.available = true/g" sandbox/etc/magma.sandbox.config

# Bug fix... create the scan directory so ClamAV unit tests work.
if [ ! -d 'sandbox/spool/scan/' ]; then
  mkdir -p sandbox/spool/scan/
fi

# Compile the daemon and then compile the unit tests.
make all; error

# Change the socket path.
sed -i -e "s/\/var\/lib\/mysql\/mysql.sock/\/var\/run\/mysqld\/mysqld.sock/g" sandbox/etc/magma.sandbox.config

# Run the unit tests.
dev/scripts/launch/check.run.sh

# If the unit tests fail, print an error, but contine running.
if [ \$? -ne 0 ]; then
  tput setaf 1; tput bold; printf "\n\nsome of the magma daemon unit tests failed...\n\n"; tput sgr0;
  for i in 1 2 3; do
    printf "\a"; sleep 1
  done
  sleep 12
fi

# Alternatively, run the unit tests atop Valgrind.
# Note this takes awhile when the anti-virus engine is enabled.
# dev/scripts/launch/check.vg

# Daemonize instead of running on the console.
# sed -i -e "s/magma.output.file = false/magma.output.file = true/g" sandbox/etc/magma.sandbox.config
# sed -i -e "s/magma.system.daemonize = false/magma.system.daemonize = true/g" sandbox/etc/magma.sandbox.config

# Launch the daemon.
# ./magmad --config magma.system.daemonize=true sandbox/etc/magma.sandbox.config

# Save the result.
# RETVAL=\$?

# Give the daemon time to start before exiting.
sleep 15

# Exit wit a zero so Vagrant doesn't think a failed unit test is a provision failure.
exit \$RETVAL
EOF

# Make the script executable.
if [ -d /home/vagrant/ ]; then
  chown vagrant:vagrant /home/vagrant/magma-build.sh
  chmod +x /home/vagrant/magma-build.sh
else
  chmod +x /root/magma-build.sh
fi

# Customize the message of the day
printf "Magma Daemon Development Environment\nTo download and compile magma, just execute the magma-build.sh script.\n\n" > /etc/motd