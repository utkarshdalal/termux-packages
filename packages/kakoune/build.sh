TERMUX_PKG_HOMEPAGE=https://kakoune.org/
TERMUX_PKG_DESCRIPTION="Code editor heavily inspired by Vim"
TERMUX_PKG_LICENSE="Unlicense"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2025.06.03"
TERMUX_PKG_SRCURL=https://github.com/mawww/kakoune/releases/download/v$TERMUX_PKG_VERSION/kakoune-$TERMUX_PKG_VERSION.tar.bz2
TERMUX_PKG_SHA256=ced5941f1bdfb8ef6b0265b00bfd7389e392fb41b2bf11990cee9d6e95316499
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libc++"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_create_debscripts() {
	cat <<- EOF > ./postinst
	#!$TERMUX_PREFIX/bin/sh
	if [ "$TERMUX_PACKAGE_FORMAT" = "pacman" ] || [ "\$1" = "configure" ] || [ "\$1" = "abort-upgrade" ]; then
		if [ -x "$TERMUX_PREFIX/bin/update-alternatives" ]; then
			update-alternatives --install \
				$TERMUX_PREFIX/bin/editor editor $TERMUX_PREFIX/bin/kak 45
		fi
	fi
	EOF

	cat <<- EOF > ./prerm
	#!$TERMUX_PREFIX/bin/sh
	if [ "$TERMUX_PACKAGE_FORMAT" = "pacman" ] || [ "\$1" != "upgrade" ]; then
		if [ -x "$TERMUX_PREFIX/bin/update-alternatives" ]; then
			update-alternatives --remove editor $TERMUX_PREFIX/bin/kak
		fi
	fi
	EOF
}
