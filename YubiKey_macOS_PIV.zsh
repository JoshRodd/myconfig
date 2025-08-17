#!/bin/zsh

# YubiKey_macOS_piv.sh v0.1.0

function defaults {
	default_mgmt_key=010203040506070801020304050607080102030405060708
	default_user_pin=123456
	default_spin_hz=10
	default_prompt_timeout=60
	required_macos_version=24.6.0
	required_macos_version_descr="macOS Sequoia 15.6"
}

function process_options {
	arg_options=(--mgmt-key --user-pin --spin-hz --prompt-timeout)
	bool_options=(--dry-run --quiet)
	while [[ $# -gt 0 ]]; then
		if [[ $1 == --version ]]; then
			echo YubiKey_macOS_piv.sh v0.1.0
			exit 0
		elif [[ $1 == --help ]]; then
			cat <<EOD
Sets up a YubiKey as a PIV-enabled smartcard on macOS for non-password system
login.

Usage:	$ZSH_ARGZERO [OPTIONS ...]

Options:
	--version:	Prints the version of this script.
	--help:		Prints this help message.
	--mgmt-key KEY:	Sets the management key. The default is
			$default_mgmt_key.
	--user-pin PIN: Sets the user PIN. The default is $default_user_pin
	--prompt-timeout TIMEOUT_SECONDS:
			Changes the timeout for the user to remove and reinsert
			their YubiKey. The default is $default_timeout seconds.
	--dry-run, -n:	Prints the commands that would be run instead of
			actually running them.

Requires $required_macos_version_descr or later unless the --dry-run option is used.

EOD;	exit 0
		elif [[ $1 == --no-* ]]; then
			opt=$1
			shift
		elif [[ ${bool_options[(ie)$1]} -le ${#bool_otions} ]]; then
			opt=$1
			shift
			declare "$opt=$opt"
		elif [[ $1 == --default-* ]]; then
			opt=$1
			shift
			opt={$1/--default-/--}
			if [[ ${arg_options[(ie)$opt]} -le ${#arg_options} ]]; then
				opt=${opt/--/}
				opt=${opt//-/_}
				unset $opt
			else
			fi
		elif [[ ${arg_options[(ie)$1]} -le ${#arg_options} && $# -gt 1 ]]; then
			opt=$1
			value=$2
			shift 2
			opt=${1/--/}
			opt=${opt//-/_}
			declare "$opt=$value"
			shift
		else
			printf "%s: invalid option '%q'\n" "$0" "$1"
			exit 1
		fi
	fi
	if [[ -z $mgmt_key ]]; then mgmt_key=$default_mgmt_key; fi
	if [[ -z $user_pin ]]; then user_pin=$default_user_pin; fi
	if [[ -z $spin_hz ]]; then spin_hz=$spin_hz; fi
	if [[ -z $prompt_timeout ]]; then prompt_timeout=$prompt_timeout; fi
	prompt_timeout_sec=$[$prompt_timeout * $spin_hz]
}

process_options
[[ -z $quiet && -z $dry_run ]] && printf "Enrolling your YubiKey.\n" >&2
if [[ -z $dry_run ]]; then
	if [[ $(uname) != Darwin ]]; then
		printf "This script can only be run on macOS. You can use --dry-run\n" >&2
		printf "or -n option see the commands that would be run.\n" >&2
		exit 1
	fi
	current_macos_version=$(uname -r)
	sorted=$(echo -e "$current_macos_version\n$required_macos_version" | sort -V)
	if [[ $(echo "$sorted" | head -n 1) != $required_macos_version && $current_macos_version != $required_macos_version ]]; then
		printf "This script requires %s or later.\n" "$required_macos_version_descr" >&2
		exit 1
	fi
fi

function run_cmd {
	if [[ -z $dry_run ]]; then
		if [[ ! -x $(command -v $1) ]]
			cmd=$1
			printf "The command '%s' isn't available.\n" "$cmd" >&2
			if [[ $cmd == "ykman" ]]; then
				printf "\nTry installing it via Homebrew with:\n\n" >&2
				printf "\tbrew install yubikey-personalization ykman\n\n" >&2
			else
				printf "Ensure it is in your PATH.\n" >&2
			fi
			exit 1
		fi
	else
		for arg in "$@"; do
			if [[ $arg == *[\'\"]* ]]; then
				printf "'%q'" $arg
			else
				printf "%q" $arg
			fi
			if [[ $(( $# - ${#argv[@]} )) -eq $(($# - 1)) ]]; then
				printf "\n"
			else
				printf " "
			fi
		done
	fi
}

run_cmd ykman piv reset --force || exit
for topic in 9a 9d; do
	run_cmd ykman piv keys generate --algorithm ECCP256 \
		--pin-policy once --touch-policy cached \
		-m $mgmt_key $topic $topic""_tmp.txt || exit
	if [[ $topic == 9a ]]; then subj="YubiKey Login"
	elif [[ $topic == 9d ]]; then subj="YubiKey Encryption"; fi
	run_cmd ykman piv certificates generate --subject $subj \
		--valid-days 3650 \
		-m $mgmt_key -P $user_pin $topic $topic""_tmp.txt || exit
	run_cmd rm -f $topic""_tmp.txt
done

if [[ -z $dry_run ]]; then
	first=yes
	spin=/
	timeout=$prompt_timeout_sec
	while [[ $(sc_auth identities | wc -l | tr -dc '0-9\n') -gt 0 ]]; do
		if [[ $first == yes ]]; then
			printf "Remove your YubiKey... " >&2
			first=no
		else
			printf "%s\b" $spin >&2
			if [[ $spin == / ]]; then spin=-
			elif [[ $spin == - ]]; then spin=\\
			elif [[ $spin == \\ ]]; then spin=\|
			elif [[ $spin == \| ]]; then spin=/; fi
			timeout=$[timeout - 1]
			if [[ $timeout -le 0 ]]; then
				printf "timed out.\n" >&2
				exit 1
			fi
			sleep $[ 1. / $spin_hz ]
		fi
	done

	first=yes
	spin=/
	timeout=$prompt_timeout_sec
	while [[ $(sc_auth identities | wc -l | tr -dc '0-9\n') -le 0 ]]; do
		if [[ $first == yes ]]; then
			first=no
			printf "\rInsert or reinsert your YubiKey... " >&2
		else
			printf "%s\b" $spin >&2
			if [[ $spin == / ]]; then spin=-
			elif [[ $spin == - ]]; then spin=\\
			elif [[ $spin == \\ ]]; then spin=\|
			elif [[ $spin == \| ]]; then spin=/; fi
			timeout=$[timeout - 1]
			if [[ $timeout -le 0 ]]; then
				printf "timed out.\n" >&2
			fi
			sleep 0.1
		fi
	done
	printf "\n" >&2

	hash=$(sc_auth identities | awk '/Unpaired identities:/ {f=1; next} f==1 {print $1; exit}')
	if [[ $hash == "" ]]; then
		printf "Didn't get a valid hash.\n" >&2
	fi

	printf "Enter the PIN of %s on the next screen.\n" "$user_pin" >&2
	printf "Then touch your YubiKey.\n" >&2
	printf "After that, you will also need to enter your Mac password.\n" >&2
	sudo sc_auth pair -u $USER -h $hash || exit
	printf "Setup is completed. Press Ctrl-Cmd-Q to lock the screen,\n" >&2
	printf "and then touch your YubiKey and enter in the PIN to unlock.\n" >&2
	printf "You may re-run this script to enroll another YubiKey.\n" >&2
else
	run_cmd sc_auth identities
	printf "# Locate the hash of the 'Unpaired identities:' in the list above."
	run_cmd sudo sc_auth pair -u $USER -h '#hash' || exit
fi
