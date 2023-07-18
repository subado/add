#!/usr/bin/env sh

PROGRAM="${0##*/}"
GETOPT="getopt"

BOLD=$(tput bold)
NORMAL=$(tput sgr0)
ITALIC=$(tput sitm)

[ "$DEBUG" ] && set -x

die() {
	echo "$PROGRAM: $*"
	echo "Try '$PROGRAM --help' for more information."
	exit 1
}

usage() {
	cat <<-_EOF
		usage: ${BOLD}$PROGRAM${NORMAL} [-h, --noinstall] [ ${ITALIC}OPTIONS${NORMAL} ]
	_EOF
}

validate_distro() {
	case "$release" in
	*$1*)
		[ "$DISTRO" ] || DISTRO="$1"
		[ "$INSTALL" ] || INSTALL="$install_cmd"
		;;
	*)
		return 1
		;;
	esac
}

set_distro_specific() {
	for file in /etc/*release; do
		if [ -r "$file" ]; then
			release="$release $(cat "$file")"
		fi
	done
	command -v lsb_release >/dev/null 2>&1 && release="$release $(lsb_release -a)"

	while read -r distrs install_cmd && { [ "$DISTRO" = "" ] || [ "$INSTALL" = "" ]; }; do
		while IFS=',' read -r distr1 distr2; do
			if validate_distro "$distr1" || { [ "$distr2" ] && validate_distro "$distr2"; }; then
				break 2
			fi
		done <<-_EOF
			$distrs
		_EOF
	done <distros

	[ "$DISTRO" ] || die "Can't identify current distribution, set DISTRO manually"
	[ "$INSTALL" ] || die "'DISTRO not match to any install command, set INSTALL manually"
}

get_overrides() {
	[ -r "overrides/$DISTRO" ] && . "overrides/$DISTRO"
}

installfail() {
	exit 1
}

install() {
	eval "$INSTALL $1" || installfail "$1" || exit 1
}

install_pkgs() {
	while [ $# -ne 0 ]; do
		cur_INSTALL="$INSTALL"
		while read -r opts pkg; do
			case "$opts" in
			-*)
				cur_INSTALL="$cur_INSTALL $opts"
				continue
				;;
			\#*) continue ;;
			esac
			INSTALL="$cur_INSTALL" install "$opts"
			cur_INSTALL="$INSTALL"
		done <"$1"
		shift
	done
}

after_clone() {
	return $?
}

clone_dots() {
	set -e
	temp=$(su -c "mktemp -d" "$user")
	su -c "git clone --recurse-submodules --depth=1 $DOTS_REPO $temp" "$user"
	set +e
	after_clone "$temp"
	[ "$DOTS_GIT_DIR" ] && su -c "mv $temp/.git $temp/$DOTS_GIT_DIR" "$user"
	{
		while read -r file; do
		cp -al "$file" "$HOME" >/dev/null 2>&1 &&
			rm -rf "$file" || exit 1
		done <<-_EOF
			$(find "$temp" -maxdepth 1 | tail -n +2)
		_EOF
	} ||
	{
		rsync -a --remove-source-files "$temp/" "$HOME/" &&
			find "$temp" -depth -type d -empty -delete || exit 1
	}
}

[ -r conf ] && . ./conf                                                                       # Get config
eval set -- "$("$GETOPT" -o hd:i:n -l help,distro:,install:,noinstall -n "$PROGRAM" -- "$@")" # Get opts

while true; do
	case $1 in
	-h | --help) usage && exit 0 ;;
	-d | --distro)
		shift
		DISTRO=$1
		shift
		;;
	-i | --install)
		shift
		INSTALL=$1
		shift
		;;
	-n | --noinstall)
		noinstall=1
		shift
		;;
	--)
		shift
		break
		;;
	esac
done

user="$1"
[ "$user" ] || die "missing user operand"
shift
HOME="$(getent passwd "$user" | cut -d: -f6)"

[ "$(id -u)" -ne 0 ] && die "run script as root"

if [ "$DISTRO" = "" ] || [ "$INSTALL" = "" ]; then
	set_distro_specific # Set distro specific
fi
get_overrides # Get overrides specified for current distro

# Install packages
[ "$noinstall" ] || install_pkgs "${BASEPKGS:=basepkgs/$DISTRO}" "${PKGS:=pkgs/$DISTRO}"

# Clone dots repo
[ "$DOTS_REPO" ] && clone_dots
