# Remote SSH Automation
# HOW TO USE:
# 	SendCommand.UNIX -u $USERNAME -p $PASSWORD --asRoot "$hostname" "whoami"
# 	SendCommand.UNIX -u $USERNAME -p $PASSWORD "$hostname" <<-EOF
#		printf "Luke, I am your father\n";
#		whoami
# 	EOF
function SendCommand.UNIX () {
	local -r VERSION="2.3.1";
	local -r SCRIPT_NAME="${FUNCNAME[0]}";

	local -r UNIQUE_SESSION_ID="$(echo $RANDOM | md5sum | awk '// { print $1 }')";

	# Styling
	local red='\033[0;31m';
	local green='\033[0;32m';
	local yellow='\033[0;33m';
	local default='\033[0m';
	local bold='\033[1m';
	local underlined="\033[4m";

	# Switches
	local NEEDS_ROOT=false;
	local OUTPUT_FILE="";
	local DEBUG=false;
	
	# Variables used by the script
	local username="";
	local password="";
	local server="";
	local commands="";

	# Check for needed programs to be present on the system.
	local dependencies=(sshpass perl printf);
	for p in "${dependencies[@]}"; do
		command -v "$p" >/dev/null 2>&1 || {
			printf "${yellow}WARNING${default} - Required program is not installed: '%s'. Install it then retry..\n" "$p";
		
			return 1;
		}
	done

	usage () {
		printf "USAGE\n" >&2;
		printf "\t${yellow}%s${default} [-r] -u ${underlined}USERNAME${default} -p ${underlined}PASSWORD${default} ${underlined}HOSTNAME_IP${default} ${underlined}COMMAND${default}\n\n" "$SCRIPT_NAME" >&2;
		printf "OPTIONS\n" >&2;
		printf "\t-u, --username ${underlined}USERNAME${default}\n" >&2;
		printf "\t\tSpecify the username used to login into the remote host\n\n" >&2;
		printf "\t-p, --password ${underlined}PASSWORD${default}\n" >&2;
		printf "\t\tSpecify the password used to login into the remote host and/or to become root (sudo su -)\n\n" >&2;
		printf "\t-r, --asRoot\n" >&2;
		printf "\t\tSend commands as the ROOT user\n\n" >&2;
		printf "\t-d, --debug\n" >&2;
		printf "\t\tEnables debug mode. The content won't be parsed and it will be shown everything that's happening on the remote host\n\n" >&2;
		printf "\t-o, --output ${underlined}FILE_PATH${default}\n" >&2;
		printf "\t\tAppends to the file specified everything happening on the remote host\n\n" >&2;
		printf "\t-h, --help\n" >&2;
		printf "\t\tDisplay this help text and exit\n\n" >&2;
		printf "\t-v, --version\n" >&2;
		printf "\t\tDisplay version information and exit\n\n" >&2;
		printf "\n" >&2;
	}
	version () {
		printf "%s, version %s\n" "${SCRIPT_NAME}" "${VERSION}";
		printf "License: GNU GPL v3.0\n\n";
		printf "Written by Luca Salvarani - https://github.com/LukeSavefrogs\n\n";
	}

	# Usage: 
	#	check_reachable "120.0.0.1"
	function check_reachable {
		local hostname_or_ip=$1;

		ssh -o PubkeyAuthentication=no -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o ChallengeResponseAuthentication=no -o ConnectTimeout=5 $hostname_or_ip 2>&1 | grep -q "Permission denied";

		ssh_return_value=$?;

		[[ $ssh_return_value == 0 ]] ||
			printf "${red}ERROR${default} - Host '%s' unreachable on port 22\n" "$hostname_or_ip";

		return $ssh_return_value;
	}

	check_credentials () {
		system_os=$(timeout 10 sshpass -p "$3" ssh -tt -o LogLevel=QUIET -o StrictHostKeyChecking=No -o ConnectTimeout=5 -l "$2" "$1" "uname" 2>/dev/null);
		ssh_return_value=$?;

		if [[ $ssh_return_value == 5 ]]; then
			printf "${red}ERROR${default} - Credentials not valid\n" >&2;
		elif [[ $ssh_return_value == 124 ]]; then
			printf "${yellow}WARNING${default} - Credentials expired (server asking to change them during login)\n" >&2;
		fi

		printf "%s\n" "$system_os" | tr -d '\r';
		return $ssh_return_value;
	}


	OPTIND=1;
	POSITIONAL=();
	while [[ $# -gt 0 ]]; do
		key="$1";
		case $key in
			-r | --asRoot)
				NEEDS_ROOT=true;
				shift;
			;;
			-u | --username)
				username="$2";
				shift;
				shift;
			;;
			-p | --password)
				password="$2";
				shift;
				shift;
			;;
			-h | --help)
				usage;

				return 0;
			;;
			-d | --debug)
				DEBUG=true;

				shift;
			;;
			-o | --output)
				OUTPUT_FILE="$2";

				[[ -z "${OUTPUT_FILE//[[:blank:]]/}" ]] && {
					printf "${red}ERROR${default} - You MUST specify the filename to append the data to\n\n" >&2;
					usage;
					return 1;
				}
				shift;
				shift;
			;;
			-V | --version)
				version;

				return 0;
			;;
			*)
				POSITIONAL+=("$1");
				shift
			;;
		esac;
	done;
	set -- "${POSITIONAL[@]}";

	# Check if REQUIRED parameters were provided
	[[ -z "$1" || -z "$username" || -z "$password" ]] && {
		[[ -z "${1//[[:blank:]]/}" ]] && printf "${red}ERROR${default} - Specify target and remote commands...\n\n" >&2;
		[[ -z "${username//[[:blank:]]/}" ]] && printf "${red}ERROR${default} - Specify USERNAME\n\n" >&2;
		[[ -z "${password//[[:blank:]]/}" ]] && printf "${red}ERROR${default} - Specify PASSWORD\n\n" >&2;

		usage;
		return 1;
	}

	server="$1";
	commands="$2"; if [[ -z "$commands" || "$commands" == "-" ]]; then commands=$(cat); fi


	$DEBUG && printf "> [-] Checking connection to '%s'... \t" "$server";
	if ! check_reachable "$server"; then 
	$DEBUG && printf "\r> [${red}X${default}] Checking connection to '%s'... \n" "$server";
		return 1;
	fi;
	$DEBUG && printf "\r> [${green}V${default}] Checking connection to '%s'... \n" "$server";

	$DEBUG && printf "> [-] Validating credentials... \t"
	if ! remote_os=$(check_credentials "$server" "$username" "$password"); then
		$DEBUG && printf "\r> [${red}X${default}] Validating credentials...\n"
		return 1;
	fi;
	$DEBUG && printf "\r> [${green}V${default}] Validating credentials...\n"

	$DEBUG && printf "> [-] Validating Operative System... \t"
	if ! [[ ${remote_os^^} =~ (^LINUX$|^AIX$|DARWIN|^CYGWIN) ]]; then
		$DEBUG && printf "\r> [${red}X${default}] Validating Operative System (OS not valid: '%s')...\n" "${remote_os}"
		return 1;
	fi;
	$DEBUG && printf "\r> [${green}V${default}] Validating Operative System...\n"

	# Function used to decode data passed through the SSH connection
	decodeRemoteScreen () {
		# Export variables to exchange data between Bash and Perl
		export PSHARED_UNIQUE_SESSION_ID="$UNIQUE_SESSION_ID";
		export PSHARED_OUTPUT_FILE="$OUTPUT_FILE";
		export PSHARED_DEBUG_MODE="$($DEBUG && echo 1 || echo 0)";

		perl -e '
			use strict;
			use warnings;
			use Fcntl;
			
			# Get environment variables from the shell
			my $UNIQUE_SESSION_ID   = $ENV{"PSHARED_UNIQUE_SESSION_ID"};
			my $OUTPUT_TO_FILE      = $ENV{"PSHARED_OUTPUT_FILE"};
			my $DEBUG_MODE          = $ENV{"PSHARED_DEBUG_MODE"};

			# Open the file handler if the logging is enabled
			if (not $OUTPUT_TO_FILE eq "") {
				sysopen(FILEHANDLE, $OUTPUT_TO_FILE, O_NONBLOCK|O_WRONLY|O_CREAT|O_APPEND) 
					or die "Cant open File: $!\n";
			}

			# Loop through the STDIN
			while (my $line = <>) {
				my $is_stderr = $line =~ m/^STDERR:$UNIQUE_SESSION_ID/;
				my $is_stdout = $line =~ m/^STDOUT:$UNIQUE_SESSION_ID/;
				
				# Send to file a sanitized version of the line
				if (not $OUTPUT_TO_FILE eq "") {
	
					# Assign to temporary variable so that actual line content is not changed
					my $sanitized_line = $line;

					# Remove all Control Characters (color codes, carriage returns, bells and other characters)
					$sanitized_line =~ s/ \e[ #%()*+\-.\/]. |
						\r | # Remove extra carriage returns also
						(?:\e\[|\x9b) [ -?]* [@-~] | # CSI ... Cmd
						(?:\e\]|\x9d) .*? (?:\e\\|[\a\x9c]) | # OSC ... (ST|BEL)
						(?:\e[P^_]|[\x90\x9e\x9f]) .*? (?:\e\\|\x9c) | # (DCS|PM|APC) ... ST
						\e.|[\x80-\x9f] //xg;
					1 while $sanitized_line =~ s/[^\b][\b]//g;  # remove all non-backspace followed by backspace

					# Write to file
					printf FILEHANDLE "$sanitized_line";
				}
				

				if ($DEBUG_MODE) {
					print("Remote: $line");
				}

				# Print only matching lines and strip out the Unique identifier
				if ($line =~ m/^(STD(OUT|ERR):)?$UNIQUE_SESSION_ID/) {
					my $out_line = $line;
					$out_line =~ s/^(STD(OUT|ERR):)?$UNIQUE_SESSION_ID//;
					$out_line =~ s/\r+//g;
					
					# Correctly redirect both STDERR and STDOUT [2021/05/13]
					if ($is_stderr) {
						printf STDERR $out_line;
					}
					else {
						printf STDOUT $out_line;
					}
				}
			}


			# Close the file handler if the logging is enabled
			if (not $OUTPUT_TO_FILE eq "") {
				close FILEHANDLE                # wait finish
					or warn $! ? "Error closing: $!" : "Ok - Closed";
			}
		'

		# Remove ENV variables
		unset PSHARED_UNIQUE_SESSION_ID;
		unset PSHARED_OUTPUT_FILE;
		unset PSHARED_DEBUG_MODE;
	}

	$DEBUG && printf "> [-] Sending commands to remote host...\n"

	# If Bash is available, use it to provide separation between STDERR and STDOUT through Command Substitution
	# Otherwise fallback to only stdout and print stderr as stdout
	# TODO: Come up with a better fallback for systems with no bash
	sshpass -p "$password" ssh -tt "$server" -l "$username" -o LogLevel=QUIET -o StrictHostKeyChecking=No <<-EOF | decodeRemoteScreen
		$($NEEDS_ROOT && {
			printf "%s\n" "printf '$password\n' | sudo -S su -; sudo su -;"; 
		})

		if command -v bash > /dev/null 2>&1; then
			bash <<END_OF_SESSION
				printf "\n"; (
					$commands
				) 2> >(sed 's/^/STDERR:${UNIQUE_SESSION_ID}/') > >(sed 's/^/STDOUT:${UNIQUE_SESSION_ID}/'); printf "\n";
			END_OF_SESSION
		else
			printf "\n"; (
				$commands
			) 2>&1 | sed 's/^/STDOUT:${UNIQUE_SESSION_ID}/'; printf "\n";
		fi;
		
		$($NEEDS_ROOT && printf "exit\n")

		exit;
	EOF

	$DEBUG && printf "\n> [${green}V${default}] Connection closed...\n"
}
