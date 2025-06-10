# Installing packages if necessary for the full operation of CGCT (main use: not in Termux devices).

termux_step_setup_cgct_environment() {
	echo "DEBUG: ===== CGCT Environment Setup Debug Info ====="
	echo "DEBUG: TERMUX_ON_DEVICE_BUILD=$TERMUX_ON_DEVICE_BUILD"
	echo "DEBUG: TERMUX_SCRIPTDIR=$TERMUX_SCRIPTDIR"
	echo "DEBUG: TERMUX_BUILT_PACKAGES_DIRECTORY=$TERMUX_BUILT_PACKAGES_DIRECTORY"
	echo "DEBUG: TERMUX_COMMON_CACHEDIR=$TERMUX_COMMON_CACHEDIR"
	echo "DEBUG: TERMUX_PREFIX=$TERMUX_PREFIX"
	echo "DEBUG: CGCT_DIR=$CGCT_DIR"
	
	[ "$TERMUX_ON_DEVICE_BUILD" = "true" ] && return

	echo "DEBUG: Installing temporary glibc"
	termux_install_temporary_glibc
	echo "DEBUG: Setting up libgcc links"
	termux_set_links_to_libgcc_of_cgct

	if [ "$TERMUX_PKG_BUILD_MULTILIB" = "true" ]; then
		echo "DEBUG: Setting up multilib environment"
		(
			termux_conf_multilib_vars
			echo "DEBUG: Installing temporary glibc for multilib"
			termux_install_temporary_glibc
			echo "DEBUG: Setting up libgcc links for multilib"
			termux_set_links_to_libgcc_of_cgct
		)
	fi
	echo "DEBUG: ===== End CGCT Environment Setup Debug Info ====="
}

# The temporary glibc is a glibc used only during compilation of simple packages
# or a full glibc that will be customized for the system and replace the temporary glibc.
termux_install_temporary_glibc() {
	local PKG="glibc"
	local multilib_glibc=false
	if [ "$TERMUX_ARCH" != "$TERMUX_REAL_ARCH" ]; then
		echo "DEBUG: Setting up multilib glibc"
		multilib_glibc=true
		PKG+="32"
	fi

	echo "DEBUG: Checking for existing temporary glibc installation"
	# Checking if temporary glibc needs to be installed.
	if [ -f "$TERMUX_BUILT_PACKAGES_DIRECTORY/$PKG-temporary-for-cgct" ]; then
		echo "DEBUG: Found existing temporary glibc marker at $TERMUX_BUILT_PACKAGES_DIRECTORY/$PKG-temporary-for-cgct"
		return
	fi
	
	echo "DEBUG: Searching for glibc build script"
	local PKG_DIR=$(ls ${TERMUX_SCRIPTDIR}/*/${PKG}/build.sh 2> /dev/null || \
		ls ${TERMUX_SCRIPTDIR}/*/${PKG}/build.sh 2> /dev/null)
	if [ -n "$PKG_DIR" ]; then
		echo "DEBUG: Found glibc build script at $PKG_DIR"
		read -r DEP_ARCH DEP_VERSION DEP_VERSION_PAC _ < <(termux_extract_dep_info $PKG "${PKG_DIR/'/build.sh'/}")
		echo "DEBUG: Extracted dependency info:"
		echo "DEBUG:   ARCH: $DEP_ARCH"
		echo "DEBUG:   VERSION: $DEP_VERSION"
		echo "DEBUG:   VERSION_PAC: $DEP_VERSION_PAC"
		if termux_package__is_package_version_built "$PKG" "$DEP_VERSION"; then
			echo "DEBUG: Package version already built"
			return
		fi
	fi

	[ ! "$TERMUX_QUIET_BUILD" = "true" ] && echo "Installing temporary '${PKG}' for the CGCT tool environment."

	local PREFIX_TMP_GLIBC="data/data/com.termux/files/usr/glibc"
	local PATH_TMP_GLIBC="$TERMUX_COMMON_CACHEDIR/temporary_glibc_for_cgct"
	echo "DEBUG: Creating temporary glibc directory at $PATH_TMP_GLIBC"
	mkdir -p "$PATH_TMP_GLIBC"

	local GPKG_LINK="https://service.termux-pacman.dev/gpkg/$TERMUX_ARCH"
	local GPKG_JSON="$PATH_TMP_GLIBC/gpkg-$TERMUX_ARCH.json"
	echo "DEBUG: Downloading GPKG info from $GPKG_LINK/gpkg.json"
	termux_download "$GPKG_LINK/gpkg.json" \
		"$GPKG_JSON" \
		SKIP_CHECKSUM

	# Installing temporary glibc.
	local GLIBC_PKG=$(jq -r '."glibc"."FILENAME"' "$GPKG_JSON")
	echo "DEBUG: Found glibc package: $GLIBC_PKG"
	if [ ! -f "$PATH_TMP_GLIBC/$GLIBC_PKG" ]; then
		echo "DEBUG: Downloading glibc package from $GPKG_LINK/$GLIBC_PKG"
		termux_download "$GPKG_LINK/$GLIBC_PKG" \
			"$PATH_TMP_GLIBC/$GLIBC_PKG" \
			$(jq -r '."glibc"."SHA256SUM"' "$GPKG_JSON")
	fi

	[ ! "$TERMUX_QUIET_BUILD" = true ] && echo "extracting temporary $PKG..."
	echo "DEBUG: Extracting temporary glibc to $PATH_TMP_GLIBC"

	# Unpacking temporary glibc.
	tar -xJf "$PATH_TMP_GLIBC/$GLIBC_PKG" -C "$PATH_TMP_GLIBC" data
	if [ "$multilib_glibc" = "true" ]; then
		echo "DEBUG: Setting up multilib glibc components"
		# Installing `lib32`.
		echo "DEBUG: Installing lib32 to $TERMUX__PREFIX__LIB_DIR"
		mkdir -p "$TERMUX__PREFIX__LIB_DIR"
		cp -r "$PATH_TMP_GLIBC/$PREFIX_TMP_GLIBC/lib/"* "$TERMUX__PREFIX__LIB_DIR"
		# Installing `include32`.
		echo "DEBUG: Installing include32 to $TERMUX__PREFIX__INCLUDE_DIR"
		mkdir -p "$TERMUX__PREFIX__INCLUDE_DIR"
		local hpath
		for hpath in $(find "$PATH_TMP_GLIBC/$PREFIX_TMP_GLIBC/include" -type f); do
			local h=$(sed "s|$PATH_TMP_GLIBC/$PREFIX_TMP_GLIBC/include/||g" <<< "$hpath")
			if [ -f "$TERMUX__PREFIX__BASE_INCLUDE_DIR/$h" ] && \
				[ $(md5sum "$hpath" | awk '{printf $1}') = $(md5sum "$TERMUX__PREFIX__BASE_INCLUDE_DIR/$h" | awk '{printf $1}') ]; then
				echo "DEBUG: Removing duplicate header file: $h"
				rm "$hpath"
			fi
		done
		find "$PATH_TMP_GLIBC/$PREFIX_TMP_GLIBC/include" -type d -empty -delete
		cp -r "$PATH_TMP_GLIBC/$PREFIX_TMP_GLIBC/include/"* "$TERMUX__PREFIX__INCLUDE_DIR"
		# Installing dynamic linker in lib.
		echo "DEBUG: Installing dynamic linker"
		mkdir -p "$TERMUX__PREFIX__BASE_LIB_DIR"
		local ld_path=$(ls "$TERMUX__PREFIX__LIB_DIR"/ld-*)
		ln -sr "${ld_path}" "$TERMUX__PREFIX__BASE_LIB_DIR/$(basename ${ld_path})"
	else
		echo "DEBUG: Installing complete glibc components to $TERMUX_PREFIX"
		# Complete installation of glibc components.
		cp -r "$PATH_TMP_GLIBC/$PREFIX_TMP_GLIBC/"* "$TERMUX_PREFIX"
	fi
	# It is necessary to reconfigure the paths in libs for correct
	# work of multilib-compilation and compilation in forked projects.
	echo "DEBUG: Reconfiguring library paths"
	grep -I -s -r -l "/$PREFIX_TMP_GLIBC/lib/" "$TERMUX__PREFIX__LIB_DIR" | xargs sed -i "s|/$PREFIX_TMP_GLIBC/lib/|$TERMUX__PREFIX__LIB_DIR/|g"

	# Marking the installation of temporary glibc.
	echo "DEBUG: Creating temporary glibc marker"
	rm -fr "$PATH_TMP_GLIBC/data"
	mkdir -p "$TERMUX_BUILT_PACKAGES_DIRECTORY"
	touch "$TERMUX_BUILT_PACKAGES_DIRECTORY/$PKG-temporary-for-cgct"
}

# Sets up symbolic links to libgcc* libraries (from cgct) in the application environment
# to allow cgct to work properly, if necessary.
termux_set_links_to_libgcc_of_cgct() {
	echo "DEBUG: Setting up libgcc links from CGCT"
	local libgcc_cgct
	mkdir -p "$TERMUX__PREFIX__LIB_DIR"
	for libgcc_cgct in $(find "$CGCT_DIR/$TERMUX_ARCH/lib" -maxdepth 1 -type f -name 'libgcc*'); do
		echo "DEBUG: Processing libgcc file: $libgcc_cgct"
		if [ ! -e "$TERMUX__PREFIX__LIB_DIR/$(basename $libgcc_cgct)" ]; then
			echo "DEBUG: Copying $libgcc_cgct to $TERMUX__PREFIX__LIB_DIR"
			cp -r "$libgcc_cgct" "$TERMUX__PREFIX__LIB_DIR"
		else
			echo "DEBUG: File already exists: $TERMUX__PREFIX__LIB_DIR/$(basename $libgcc_cgct)"
		fi
	done
}


