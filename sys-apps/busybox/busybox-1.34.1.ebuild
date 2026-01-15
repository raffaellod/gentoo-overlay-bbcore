# Copyright 1999-2020 Gentoo Authors
# Copyright 2021, 2022, 2026 Raffaello D. Di Napoli
# Distributed under the terms of the GNU General Public License v2

# See `man savedconfig.eclass` for info on how to use USE=savedconfig.

EAPI=7

inherit flag-o-matic savedconfig toolchain-funcs

DESCRIPTION="Utilities for rescue and embedded systems"
HOMEPAGE="https://www.busybox.net/"
if [[ ${PV} == "9999" ]] ; then
	MY_P=${P}
	EGIT_REPO_URI="https://git.busybox.net/busybox"
	inherit git-r3
else
	MY_P=${PN}-${PV/_/-}
	SRC_URI="https://www.busybox.net/downloads/${MY_P}.tar.bz2"
	KEYWORDS="amd64 arm arm64 x86"
fi

LICENSE="GPL-2" # GPL-2 only
SLOT="0"
# Some USE flags allow BusyBox to satisfy virtuals:
# awk		virtual/awk::bbcore (::gentoo does not check for USE=awk)
# less		virtual/pager::bbcore
# man		virtual/man::bbcore
# syslog	virtual/logger::gentoo
# vi		virtual/editor::bbcore
# mta		virtual/mta::bbcore
IUSE="awk debug dhcp dhcpd eselect-sh ipv6 less make-symlinks man math mdev mta ntp pam selinux static syslog systemd vi"
REQUIRED_USE="pam? ( !static )"
RESTRICT="test"

COMMON_DEPEND="!static? ( selinux? ( sys-libs/libselinux ) )
	pam? ( sys-libs/pam )
	virtual/libcrypt:="
DEPEND="${COMMON_DEPEND}
	static? (
		virtual/libcrypt[static-libs]
		selinux? ( sys-libs/libselinux[static-libs(+)] )
	)
	>=sys-kernel/linux-headers-2.6.39"
RDEPEND="${COMMON_DEPEND}
	mdev? ( !<sys-apps/openrc-0.13 )"

S="${WORKDIR}/${MY_P}"

busybox_config_option() {
	local flag=$1 ; shift
	if [[ ${flag} != [yn] && ${flag} != \"* ]] ; then
		busybox_config_option $(usex ${flag} y n) "$@"
		return
	fi
	local expr
	while [[ $# -gt 0 ]] ; do
		case ${flag} in
		(y) expr="s:.*\<CONFIG_$1\>.*set:CONFIG_$1=y:g" ;;
		(n) expr="s:CONFIG_$1=y:# CONFIG_$1 is not set:g" ;;
		(*) expr="s:.*\<CONFIG_$1\>.*:CONFIG_$1=${flag}:g" ;;
		esac
		sed -i -e "${expr}" .config || die
		einfo "$(grep "CONFIG_$1[= ]" .config || echo "Could not find CONFIG_$1 ...")"
		shift
	done
}

busybox_config_enabled() {
	local val=$(sed -n "/^CONFIG_$1=/s:^[^=]*=::p" .config)
	case ${val} in
	('') return 1 ;;
	(y)  return 0 ;;
	(*)  echo "${val}" | sed -r 's:^"(.*)"$:\1:' ;;
	esac
}

# Patches go here!
PATCHES=(
	"${FILESDIR}"/${PN}-1.34.1-gcc-14.patch

	# "${FILESDIR}"/${P}-*.patch
)

src_prepare() {
	default
	unset KBUILD_OUTPUT # Gentoo #88088
	append-flags -fno-strict-aliasing # Gentoo #310413
	if use ppc64; then
		append-flags -mminimal-toc # Gentoo #130943
	fi

	# Flag cleanup.
	sed -i -r \
		-e 's:[[:space:]]?-(Werror|Os|falign-(functions|jumps|loops|labels)=1|fomit-frame-pointer)\>::g' \
		Makefile.flags || die
	sed -i '/^#error Aborting compilation./d' applets/applets.c || die
	if use elibc_glibc; then
		sed -i 's:-Wl,--gc-sections::' Makefile
	fi
	sed -i \
		-e "/^CROSS_COMPILE/s:=.*:= ${CHOST}-:" \
		-e "/^AR\>/s:=.*:= $(tc-getAR):" \
		-e "/^CC\>/s:=.*:= $(tc-getCC):" \
		-e "/^HOSTCC/s:=.*:= $(tc-getBUILD_CC):" \
		-e "/^PKG_CONFIG\>/s:=.*:= $(tc-getPKG_CONFIG):" \
		Makefile || die
}

src_configure() {
	# check for a busybox config before making one of our own.
	# if one exist lets return and use it.
	local newconfig
	restore_config .config
	if [ -f .config ]; then
		newconfig=false
	else
		newconfig=true
		ewarn 'Could not locate user configfile, so we will save a default one'
		# Setup the config file.
		emake -j1 -s allyesconfig >/dev/null
		# NOMMU forces a bunch of things off which we want on; Gentoo #387555.
		busybox_config_option n NOMMU
		sed -i '/^#/d' .config
	fi
	yes '' | emake -j1 -s oldconfig >/dev/null

	# Now turn off stuff we really don't want.

	# When selected as system shell with preference for built-ins, this simple
	# implementation is run instead of the real ar, breaking builds.
	busybox_config_option n AR
	busybox_config_option n BUILD_AT_ONCE
	busybox_config_option n BUILD_LIBBUSYBOX
	busybox_config_option n DMALLOC
	# Gentoo #607548
	busybox_config_option n FEATURE_2_4_MODULES
	# It could enable bitrotten (rarely tested) code.
	busybox_config_option n FEATURE_CLEAN_UP
	# Only controls mounting with <linux-2.6.23 .
	busybox_config_option n FEATURE_MOUNT_NFS
	busybox_config_option n FEATURE_SUID_CONFIG
	# Triming the BSS size may be dangerous.
	busybox_config_option n FEATURE_USE_BSS_TAIL
	busybox_config_option n USE_PORTABLE_CODE
	busybox_config_option n WERROR
	# All the debug options are compiler related, so punt them.
	busybox_config_option n DEBUG_SANITIZE
	busybox_config_option n DEBUG
	busybox_config_option n DMALLOC
	busybox_config_option n EFENCE
	busybox_config_option y NO_DEBUG_LIB
	if use elibc_glibc; then
		# glibc-2.26 and later does not ship RPC implientation.
		busybox_config_option n FEATURE_HAVE_RPC
		busybox_config_option n FEATURE_INETD_RPC
	elif use elibc_musl; then
		# These cause trouble with musl.
		busybox_config_option n EXTRA_COMPAT
		busybox_config_option n FEATURE_UTMP
		busybox_config_option n FEATURE_VI_REGEX_SEARCH
	elif use elibc_uclibc; then
		# Disable features that uClibc doesn't (yet?) provide.
		busybox_config_option n FEATURE_SYNC_FANCY # Gentoo #567598
		busybox_config_option n NSENTER
	fi

	if ${newconfig}; then
		if use elibc_uclibc; then
			# If these are not set and we are using a uclibc/busybox setup
			# all calls to system() will fail.
			busybox_config_option y {,SH_IS_}ASH
			busybox_config_option n {,SH_IS_}HUSH
		fi

		# Default to off a bunch of uncommon options, as well as those
		# we support via USE flags, which will be re-enabled later if
		# the corresponding USE flag is set.
		busybox_config_option n \
			ADD_SHELL ASH_OPTIMIZE_FOR_SIZE \
			BEEP BOOTCHARTD \
			CHPST CRONTAB \
			DC DEVFSD DHCPRELAY DNSD DPKG{,_DEB} DUMPLEASES \
			ENVDIR ENVUIDGID \
			FAKEIDENTD FBSPLASH FEATURE_{DEVFS,NTPD_SERVER} FOLD FSCK_MINIX FTP{D,GET,PUT} \
			HALT HOSTID HTTPD HUSH \
			INETD INIT INOTIFYD IPCALC \
			KLOGD \
			LINUXRC LOCALE_SUPPORT LOGGER LOGNAME LPD \
			MAKEMIME MINIPS MKFS_MINIX MSH \
			NTPD \
			OD \
			POWER{OFF,TOP} \
			RDEV READPROFILE REBOOT REFORMIME REMOVE_SHELL RESUME RFKILL RPM RPM2CPIO RUN_INIT RUNSV{,DIR} \
			SETUIDGID SLATTACH SH_IS_HUSH SHELL_HUSH SMEMCAP SOFTLIMIT SULOGIN SV{,C,LOGD,OK} SYSLOGD \
			TASKSET TCPSVD TFTP_DEBUG \
			UBI{ATTACH,DETACH,{MK,RM,RS,UPDATE}VOL} UDHCP{C,C6,D} UDPSVD UU{DE,EN}CODE
		busybox_config_option '"/run"' PID_FILE_PATH
		busybox_config_option '"/run/ifstate"' IFUPDOWN_IFSTATE_PATH
	fi

	# Apply USE flags.

	# These flags to force turning on their respective applets, but
	# don’t force turning them off just because the flag isn’t set.

	# Disabling either of these means not getting a DHCPv6 client.
	if ! use dhcp || ! use ipv6; then
		busybox_config_option n UDHCPC6
	fi
	if use eselect-sh; then
		busybox_config_option y {,SH_IS_}ASH
		# TODO more
	fi
	# Don’t enable IPv6 applets; let the user take care of that.
	if ! use ipv6; then
		busybox_config_option n TRACEROUTE6
		busybox_config_option n PING6
	fi
	# Don’t disable this; NTPD_SERVER requires it, and we don’t control that one.
	if use ntp; then
		busybox_config_option y NTPD
	fi
	if use syslog; then
		busybox_config_option y {K,SYS}LOGD LOGREAD
		busybox_config_option y FEATURE_{IPC_SYSLOG,SYSLOGD_PRECISE_TIMESTAMPS}
		busybox_config_option n FEATURE_KMSG_SYSLOG
	fi

	# These other flags toggle the corresponding config on AND off,
	# overriding saved config every time.

	busybox_config_option awk AWK
	busybox_config_option dhcp UDHCPC
	busybox_config_option dhcpd DUMPLEASES UDHCPD
	busybox_config_option ipv6 FEATURE_IPV6
	busybox_config_option less LESS
	busybox_config_option man MAN
	busybox_config_option math FEATURE_AWK_LIBM
	busybox_config_option mta SENDMAIL
	busybox_config_option pam PAM
	busybox_config_option selinux SELINUX
	busybox_config_option static STATIC{,_LIBGCC}
	busybox_config_option systemd FEATURE_SYSTEMD
	busybox_config_option vi VI

	emake -j1 oldconfig >/dev/null
}

src_compile() {
	unset KBUILD_OUTPUT # Gentoo #88088
	export SKIP_STRIP=y

	emake V=1 busybox
}

src_install() {
	unset KBUILD_OUTPUT # Gentoo #88088
	save_config .config

	into /
	dodir /bin
	newbin busybox_unstripped busybox
	if use mdev; then
		dodir /$(get_libdir)/mdev/
		use make-symlinks || dosym /bin/busybox /sbin/mdev
		cp "${S}"/examples/mdev_fat.conf "${ED}"/etc/mdev.conf

		exeinto /$(get_libdir)/mdev/
		doexe "${FILESDIR}"/mdev/*

		newinitd "${FILESDIR}"/mdev.initd mdev
	fi
	if use ntp; then
		newconfd "${FILESDIR}/ntpc.confd" busybox-ntpc
		newinitd "${FILESDIR}/ntpc.initd" busybox-ntpc
		if busybox_config_enabled FEATURE_NTPD_SERVER; then
			newconfd "${FILESDIR}/ntpd.confd" busybox-ntpd
			newinitd "${FILESDIR}/ntpd.initd" busybox-ntpd
		fi
	fi
	if use syslog; then
		newconfd "${FILESDIR}/sysklogd.confd" busybox-sysklogd
		newinitd "${FILESDIR}/sysklogd.initd" busybox-sysklogd
	fi
	if busybox_config_enabled UDHCPC; then
		local path=$(busybox_config_enabled UDHCPC_DEFAULT_SCRIPT)
		exeinto "${path%/*}"
		newexe examples/udhcp/simple.script "${path##*/}"
	fi
	if busybox_config_enabled UDHCPD; then
		insinto /etc
		doins examples/udhcp/udhcpd.conf
	fi
	if busybox_config_enabled WATCHDOG; then
		newconfd "${FILESDIR}/watchdog.confd" busybox-watchdog
		newinitd "${FILESDIR}/watchdog.initd" busybox-watchdog
	fi

	# Bundle up the symlink files for use later.
	emake DESTDIR="${ED}" install
	rm _install/bin/busybox
	# For compatibility, provide /usr/bin/env.
	mkdir -p _install/usr/bin
	ln -s /bin/env _install/usr/bin/env
	tar cf busybox-links.tar -C _install .
	insinto /usr/share/${PN}
	use make-symlinks && doins busybox-links.tar

	dodoc AUTHORS README TODO

	cd docs
	docinto txt
	dodoc *.txt
	docinto pod
	dodoc *.pod
	docinto html
	dodoc *.html

	cd ../examples
	docinto examples
	dodoc inittab depmod.pl *.conf *.script undeb unrpm
}

pkg_preinst() {
	if use make-symlinks; then
		mv "${ED}"/usr/share/${PN}/busybox-links.tar "${T}"/ || die
	fi
}

pkg_postinst() {
	savedconfig_pkg_postinst

	if use make-symlinks; then
		cd "${T}" || die
		mkdir _install
		safelinks=$(
			tar tf busybox-links.tar |
			grep -v '/$' |
			while read f; do
				PATH="${ROOT}/usr/sbin:${ROOT}/usr/bin:${ROOT}/sbin:${ROOT}/bin" \
				which "$(basename ${f})" >/dev/null 2>&1 ||
				echo "${f}"
			done
		)
		[[ -n "${safelinks}" ]] || die "no links to copy safely, would destroy your system: remove USE=make-symlinks"
		tar xf busybox-links.tar -C _install ${safelinks} || die
		cp -vpPR _install/* "${ROOT}"/ || die "copying links for ${x} failed"
	fi
}
