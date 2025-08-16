#!/bin/zsh

printf "Enrolling your YubiKey.\n" >&2

if [[ -z $mgmt_key ]]; then
	mgmt_key="010203040506070801020304050607080102030405060708"; fi
if [[ -z $user_pin ]]; then user_pin="123456"; fi
if [[ -z $spin_hz ]]; then spin_hz=10; fi
if [[ -z $prompt_timeout ]]; then prompt_timeout=30; fi
prompt_timeout=$[$prompt_timeout * $spin_hz]

ykman piv reset --force || exit
for topic in 9a 9d; do
	ykman piv keys generate --algorithm ECCP256 \
		--pin-policy once --touch-policy cached \
		-m $mgmt_key $topic $topic""_tmp.txt || exit
	if [[ $topic == 9a ]]; then subj="YubiKey Login"
	elif [[ $topic == 9d ]]; then subj="YubiKey Encryption"; fi
	ykman piv certificates generate --subject $subj \
		--valid-days 3650 \
		-m $mgmt_key -P $user_pin $topic $topic""_tmp.txt || exit
	rm -f $topic""_tmp.txt
done

first=yes
spin=/
timeout=$prompt_timeout
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
timeout=$prompt_timeout
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
