#!/usr/bin/env sh

INSTALLED_PKGS="$(qlist -I)" || die "Please install app-portage/portage-utils"

install() {
	if [ "$2" ]; then
		[ -d "/etc/portage/package.use/${1%/*}" ] || mkdir -p "/etc/portage/package.use/${1%/*}"
		[ -r "/etc/portage/package.use/$1" ] && rm "/etc/portage/package.use/$1"
		IFS=' ' printf '%s\n' "$*" >>"/etc/portage/package.use/$1"
	fi
	case "$INSTALLED_PKGS" in
		*"$1"*)
			return 0
			;;
	esac
	log="$(mktemp)"
	eval "$INSTALL $1" >"$log" 2>&1 || installfail "$1" "$log" || exit 1
	rm "$log"
}

installfail() {
	
	is_fixed=1

	case "$(emerge -s "$1")" in
		*"$1 [ Masked ]"*)
			autounmask_file='/etc/portage/package.accept_keywords/zzz_autounmask'
			[ -f "$autounmask_file" ] || touch "$autounmask_file"
			set -e
			emerge --autounmask --autounmask-continue "$1"
			mkdir -p "/etc/portage/package.accept_keywords/${1%/*}"
			mv "$autounmask_file" "/etc/portage/package.accept_keywords/$1"
			set +e
			return 0
			;;
		*)
			is_fixed=
			;;
	esac

	if [ "$is_fixed" = "" ]; then
		case "$(cat "$2")" in
		*)
			return 1
			;;
		esac
	fi

	"$INSTALL" "$1" || return 1
}
