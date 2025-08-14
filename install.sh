#! /bin/zsh

# v1.1

case $(uname -o) in
	GNU/Linux) OS=linux; OS_FAMILY=unix;;
	Darwin) OS=darwin; OS_FAMILY=unix;;
esac

file=$(mktemp /tmp/myconfig.XXXXXXX)
trap "rm $file" EXIT

this_user=$USER
# Aliases for usernames
if [[ $this_user == "sam" ]]; then this_user=dracowizard; fi

# Handle hostnames that have the domain part specified
this_host=$(printf "%s\n" $HOST | cut -d. -f1)

last_installed=""
find . -path ./.git -prune -o -type f \! -name install.sh -print | while read src; do
	zshexpn=no
	if_os=
	if_user=
	if_host=
	grep -E '@!\w+:' $src | sed -E 's/^.*@!//' | while IFS=: read -Ar cmd; do
		case $cmd[1] in
			os) if_os=$cmd[2];;
			user) if_user=$cmd[2];;
			host) if_host=$cmd[2];;
			zshexpn) zshexpn=yes;;
		esac
		if [[ -n $if_os && $if_os != $OS && $if_os != $OS_FAMILY ]]; then
			continue
		fi
		if [[ -n $if_user && $if_user != $USER && $if_user != $this_user ]]; then
			continue
		fi
		if [[ -n $if_host && $if_host != $HOST && $if_host != $this_host ]]; then
			continue
		fi
		case $cmd[1] in
			install)
				dst=${(e)cmd[3]}
				instsrc=$src
				if [[ $zshexpn == yes ]]; then
					contents=$(cat $src)
					contents=${(e)contents}
					printf "%s\n" $contents > $file
					instsrc=$file
				fi

				install -d -m 755 $(dirname $dst)
				install -m ${cmd[2]} $instsrc $dst
				if [[ $zshexpn == yes ]]; then
					marker=">>"
				else
					marker="->"
				fi
				printf "%s %s %s\n" "$src" "$marker" "$dst"

				# Store the last installed file so we can hardlink to it
				last_installed=$dst
				;;
			hardlink)
				if [[ -z $last_installed ]]; then
					echo Cannot hardlink without installing a file first.
					exit 1
				fi
				src=$last_installed
				dst=${(e)cmd[2]}
				ln -f $src $dst
				echo "$src => $dst"
				;;
			postexec)
				# uncomment once i'm sure this does the right thing
				# ${=cmd[2]}
				echo "NOT IMPLEMENTED exec $cmd[2]"
				;;
		esac
	done
done

