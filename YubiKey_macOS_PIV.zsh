#!/bin/zsh

# YubiKey_macOS_piv.sh v0.1.0
# Licensed under MIT license; see the file LICENSE for details.

function help {
	cat <<EOD

Sets up a YubiKey as a PIV-enabled smartcard on macOS for non-password system
login and sets up GnuPG.

Usage:	$ZSH_ARGZERO [OPTIONS ...]

Options:
	--version:	Prints the version of this script.
	--help:		Prints this help message.
	--mgmt-key KEY:	Sets the management key. The default is
			$mgmt_key.
	--user-pin PIN: Sets the user PIN. The default is $user_pin.
	--prompt-timeout TIMEOUT_SECONDS:
			Changes the timeout for the user to remove and reinsert
			their YubiKey. The default is $prompt_timeout seconds.
	--dry-run, -n:	Prints the commands that would be run instead of
			actually running them.
	--wipe:		Replaces the current pairing even if it already seems
			exist and be valid.
	--no-reset:	Don't remove existing credentials on a YubiKey.
	--no-piv:	Skip PIV login setup.
	--no-gpg:	Skip GnuPG setup.

Requires macOS $mac_required_version or later unless the --dry-run option is used.

EOD
}

function load_defaults {
	mgmt_key=010203040506070801020304050607080102030405060708
	user_pin=123456
	spin_hz=10
	prompt_timeout=60
	piv=--piv
	gpg=--gpg
	reset=--reset
	check_versions=--check-versions
}

script_name=YubiKey_macOS_piv.sh
script_version=0.1.0
mac_required_version="Sequoia 15.6"

function check_os {
	require_version macOS 24.6.0 "" $mac_required_version
	require_version brew 4.6.3
	pkgs="ykman yubikey-personalization"
	require_version ykman 5.7.2 $pkgs
	if [[ -n $gpg ]]; then
		pkgs="gnupg pinentry-mac git"
		require_version gpg 2.4.8 $pkgs
		require_version pinentry-mac 1.3.1.1 $pkgs
		require_version git 2.50.1 $pkgs
	fi
}

function process_options {
	arg_options=(--mgmt-key --user-pin --spin-hz --prompt-timeout)
	bool_options=(--dry-run --quiet --force --wipe --reset --check-versions --piv --gpg --verbose)
	typeset -A aliases
	aliases=(
		"-n" "--dry-run"
		"-q" "--quiet"
		"-v" "--verbose"
		"-f" "--force"
	)
	while [[ $# -gt 0 ]]; do
		opt=$1; shift
		opt_equals="${opt%%=*}"
		opt_value="${opt#*=}"
		if [[ -n ${aliases[$opt]} ]]; then
			opt=${aliases[$opt]}
		fi
		if [[ $opt == --version ]]; then
			printf "%s v%s\n" $script_name $script_version
			exit 0
		elif [[ $opt == --help ]]; then
			help
			exit 0
		elif [[ $opt == --no-* ]]; then
			opt=${opt/--no-/--}
			if [[ ${arg_options[(ie)$opt]} -le ${$#arg_options} ]]; then
				opt=${opt/--/}
				opt=${opt//-/_}
				unset $opt
			else
				printf "%s: invalid option %q\n" $ZSH_ARGZERO $opt
				exit 1
			fi
		elif [[ ${bool_options[(ie)$opt]} -le ${#bool_options} ]]; then
			value=$opt
			opt=${opt/--/}
			opt=${opt//-/_}
			eval "$opt=$value"
		elif [[ $opt == --default-* ]]; then
			opt=${opt/--default-/--}
			if [[ ${arg_options[(ie)$opt]} -le ${#arg_options} ]]; then
				opt=${opt/--/}
				opt=${opt//-/_}
				unset $opt
			else
				printf "%s: invalid option %q\n" $ZSH_ARGZERO $opt
				exit 1
			fi
		elif [[ $opt == *=* && ${arg_options[(ie)$opt_equals]} -le ${#arg_options} ]]; then
			opt=$opt_equals
			opt=${opt/--/}
			opt=${opt//-/_}
			eval "$opt=$opt_value"
		elif [[ ${arg_options[(ie)$opt]} -le ${#arg_options} && $# -gt 0 ]]; then
			value=$1; shift
			opt=${opt/--/}
			opt=${opt//-/_}
			eval "$opt=$value"
		else
			printf "%s: invalid option %q\n" $ZSH_ARGZERO $opt
			exit 1
		fi
	done
	prompt_timeout_sec="$[$prompt_timeout * $spin_hz]"
}

# Checks if a component is at an installed version.
# Argument 1: component name (brew, gpg, ykman, etc.)
# Argument 2: minimum version
# Argument 3: optional space-separated list of packages to install with Homebrew
# Argument 4: optional "friendly" name instead of version number
# If Argument 1 is "macOS", the command will be uname -r;
# otherwise it will be <component name> --version.

function require_version {
	component=$1
	required=$2
	if [[ $# -le 2 || $3 == "" ]]; then packages=$component; else packages=$3; fi
	if [[ $# -le 3 ]]; then descr="$component $required"; else descr="$component $4"; fi
	if [[ -n $dry_run && -z $quiet ]]; then
		printf "# Ensure %s is version %s+" $component $required
		[[ -n $descr ]] && printf " (%s)" $descr
		printf "\n"
		return
	fi
	if [[ $component == "macOS" ]]; then
		if [[ $(uname) != Darwin ]]; then
			printf "This script can only be run on %s+. You can\n" "$descr" >&2
			printf "use the --dry-run or -n option see the commands that would be run.\n" >&2
			exit 1
		fi
		installed=$(uname -r) || exit
	else
		if [[ ! -x $(command -v $component) ]]; then
			if [[ -x /opt/homebrew/bin/$component || -x /usr/local/bin/$component ]]; then
				printf "The command '%s' isn't in your PATH. Ensure Homebrew\n" $component >&2
				printf "is properly installined, including ensuring /opt/homebrew/bin\n" >&2
				printf "and/or /usr/local/bin are in your PATH.\n" >&2
				exit 1
			fi
			printf "The command '%s' isn't installed.\n" "$component" >&2
			if  [[ $component == "brew" ]]; then
				printf "\nGo to https://brew.sh/ for instructions on installing Homebrew.\n\n" >&2
			else
				printf "\nTry installing it via Homebrew with:\n\n" >&2
				printf "\tbrew install %s\n\n" $packages >&2
			fi
			exit 1
		fi
		installed=$($component --version | head -1 | tr ' ' '\n' | grep -E -e '\d+.*\.' | head -1)
		if [[ $installed == "" ]]; then
			printf "The command '%s --version' did not produce correct output.\n" >&2
			exit 1
		fi
	fi
	sorted=$(echo -e "$installed\n$required" | sort -V)
	if [[ $(echo "$sorted" | head -n 1) != $required && $installed != $required ]]; then
		printf "This script requires %s+" $descr >&2
		if [[ $component == macOS ]]; then
			printf ".\n" >&2
		elif [[ $component == brew ]]; then
			printf "; version currently installed is %s.\n" $installed >&2
			printf "\nTry upgrading it with:\n\n\t%s update\n\n" $component >&2
		else
			printf "; version currently installed is %s.\n" $installed >&2
			installed_dir=$(basename $(command -v $component))
			if [[ $installed_dir == "/usr/local/bin" || $installed_dir == "/opt/homebrew/bin" ]]; then
				printf "\nTry upgrading it via Homebrew with:\n\n" >&2
				printf "\tbrew upgrade %s\n\n" $packages >&2
			else
				printf "\nTry installing the newer version via Homebrew with:\n\n" >&2
				printf "\tbrew install %s || brew upgrade %s\n\n" $packages $packages >&2
			fi
		fi
		exit 1
	fi
}

function run_cmd {
	if [[ -z $dry_run ]]; then
		cmd=$1
		shift
		if [[ ! -x $(command -v $cmd) ]]; then
			printf "The command '%s' isn't installed.\n" "$cmd" >&2
			exit 1
		else
			$cmd "$@"
		fi
	else
		idx=0
		for arg in "$@"; do
			idx=$[$idx + 1]
			printf "%q" $arg
			if [[ $# -eq $idx ]]; then
				printf "\n"
			else
				printf " "
			fi
		done
	fi
}

function piv_get_active {
	active_hash=$(sc_auth identities awk -v user="$USER" '/Paired identities which are used for authentication:/{p=1;next} p&&/Unpaired identities:/{p=010} &&$2==user{print $1}')
}

function piv_setup {
	# Ensure the active YubiKey isn't already configured.
	if [[ -z $wipe ]]; then
		piv_get_active
		if [[ $active_hash != "" ]]; then
			printf "%s: Your YubiKey appears to already be configured. To replace\n" $ZSH_ARGZERO >&2
			printf "it anyway, run:\n\n\t%s --wipe\n" $ZSH_ARGZERO >&2
			exit 0
		fi
	fi

	[[ -z $no_reset ]] && run_cmd ykman piv reset --force || exit
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
		printf "# Locate the hash of the 'Unpaired identities:' in the list above.\n"
		run_cmd sudo sc_auth pair -u $USER -h '#hash' || exit
	fi
}

function appendfile {
	if [[ $# -gt 0 ]]; then
		pat=$1; shift
		grep -Eq $pat $filename; rc=$?
		if [[ $rc -eq 1 ]]; then printf "%s\n" $record >> $filename || exit
		elif [[ $rc -gt 1 ]]; then exit 1; fi
	else
		fgrep -qx $record $filename; rc=$?
		if [[ $rc -eq 1 ]]; then printf "%s\n" $record >> $filename || exit
		elif [[ $rc -gt 1 ]]; then exit 1; fi
	fi
}

function gpg_setup {
	# Turn off the OTP application which is generally unhelpfull.
	run_cmd ykman config usb -f -e fido2 -e openpgp -d otp
	# Require touch for GnuPG signing operations.
	run_cmd ykman opengpg keys set-touch sig on || exit
	run_cmd ykman opengpg keys set-touch enc on || exit
	run_cmd ykman opengpg keys set-touch aut on || exit
	[[ -d ~/.gnupg || -n $dry_run ]] || (mkdir -p ~/.gnupg && chmod 700 ~/.gnupg) || exit
	if ! email_addr=$(git config --global user.email); then
		cat >&2 <<EOD

Please configure your e-mail address in Git with these commands:

	git config --global user.email you@example.com
	git config --global user.name "Your Name"

EOD
		exit 1
	fi
	if ! gecos=$(git config --global user.name); then
		gecos=$(dscl . -read /Users/$(whoami) RealName | awk -F': ' 'NR==2 {sub(/^[ \t]+/, ""); print $NF}') || exit
		run_cmd git config --global user.name $gecos || exit
	fi
	printf "Use the email '%s' and name '%s' when creating your GnuPG key.\n" $email_addr $gecos >&2
	if [[ -z $dry_run ]]; then
		filename=~/.gnupg/gpg-agent.conf
		[[ ! -f $filename ]] && touch $filename || exit
		record="pinentry-program $(command -v pinentry-mac)" appendfile
		record="default-cache-ttl 7200" appendfile "^\s*default-cache-ttl "
		record="max-catch-ttl 7200" appendfile "^\s*max-catch-ttl "
	fi
	run_cmd gpg --full-generate-key
	run_cmd git config --global gpg.program $(command -v gpg)
	run_cmd gpgconf --kill gpg-agent
	run_cmd gpg-connect-agent killagent /bye
	run_cmd gpg-connect-agent /bye
	cat >&2 <<EOD

To GPG-sign your commits:

	git config --global user.signingkey <signature>
	git config --global commit.gpgsign true

To see your key signature, run:

	gpg --list-secret-keys --keyid-format LONG

The keys on your YubiKey will be marked with "sec>". The keys stored on your
computer will be marked with just "sec".

To obtain your GPG public key for adding to GitLab or GitHub:

	gpg --armor --export <signature>

EOD
}

load_defaults
process_options "$@"
[[ -n $check_versions ]] && check_os
[[ -n $piv ]] && piv_setup
[[ -n $gpg ]] && gpg_setup
exit 0
