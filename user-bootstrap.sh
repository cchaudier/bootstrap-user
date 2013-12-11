#!/bin/bash

set -ue

TRIM="sed -e 's/^ *//g' -e 's/ *$//g'"

get_user () {
	if [ -z ${SUDO_USER+x} ]; then
		USER=$(whoami)
	else
		USER="$SUDO_USER"
	fi
	echo "$USER"	
}

get_public_key () {
	USER=$(get_user)
	cat $(eval echo ~$USER)/.ssh/id_rsa.pub
}

create_user_put_pub_key () {
	HOST="$1"
	PORT="$2"
	SSH_USER="$3"
	NEW_USER=$(get_user)
	NEW_USER_PUB_KEY=$(get_public_key)

	CMDS=$(cat <<EOF
set -x
sudo adduser --disabled-password --ingroup sudo --gecos "" $NEW_USER
sudo su $NEW_USER -c "mkdir -p ~$NEW_USER/.ssh"
sudo su $NEW_USER -c "echo \"$NEW_USER_PUB_KEY\" > ~$NEW_USER/.ssh/authorized_keys"
EOF
)

	REMOTE_SCRIPT="/tmp/${NEW_USER}_setup.sh"
	echo "$CMDS" | ssh $SSH_USER@$HOST -p $PORT "cat > $REMOTE_SCRIPT && bash $REMOTE_SCRIPT && rm -rf $REMOTE_SCRIPT"
}

search () {
	NETWORK="$1"
	PREFIX="$2"
	SSH_USER="$3"
	nmap -p 22 --open -sV -O -oG - $NETWORK/$PREFIX | while read LINE;
	do
		RES=$(echo $LINE | awk '{ match($0, /Host: ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) \(([^)]+)\) Ports: 22\/open\/tcp\/\/ssh\/\/([^\/]+)\/(.+)/, m); if(m[1] != "") printf("%s!%s!%s!%s!%s\n",m[1],m[2],m[3],m[4],m[5]); }')
		if [ -n "$RES" ]; then
			IP=$(echo $RES | awk -F! 'END { print $1 }' | eval "$TRIM")
			HOST=$(echo $RES | awk -F! 'END { print $2 }' | eval "$TRIM")
			OPENSSH=$(echo $RES | awk -F! 'END { print $3 }' | eval "$TRIM")
			MACHINE=$(echo $RES | awk -F! 'END { print $4 }' | eval "$TRIM")

			echo
			echo "Found:"
			echo "	IP: $IP ($HOST)"
			echo "	$OPENSSH"
			echo "	$MACHINE"
			echo

			if [ -n "$SSH_USER" ]; then
				read -p "Push to machine (Y/n) " -n 1 -r </dev/tty
				echo

				if [ "$REPLY" = "Y" ]; then
					echo "Pushing!"
					create_user_put_pub_key "$HOST" 22 $SSH_USER
				fi
			fi

		fi
	done
}

show_usage_and_exit () {
	echo "$(cat <<EOF
USAGE:
	push [ip] as [user]
	search [network] [prefix]
	search_and_push [network] [prefix] as [user]
EOF
)"
	exit 1
}

if [ "$#" -lt 2 ]; then
	show_usage_and_exit
fi

case "$1" in
	push)
		if [ "$#" -eq 4 ]; then
			echo "Pushing"
			echo
			create_user_put_pub_key "$2" 22 "$4"
			exit 0
		fi
		;;
	search)
		if [ "$#" -eq 3 ]; then
			echo "Searching"
			echo 
			search "$2" "$3" ""
			exit 0
		fi
		;;
	search_and_push)
		if [ "$#" -eq 5 ]; then
			echo "Searching (with option to push)"
			echo
			search "$2" "$3" "$5"
			exit 0
		fi
		;;
esac

show_usage_and_exit
