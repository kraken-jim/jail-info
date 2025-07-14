#!/usr/bin/env bash

set -e

#==================================================
#
#	Extract jail info from /etc/jail.conf files
#
#==================================================


#	jail-info.sh list
#
#		print a tab-delimited list of jails configured in /etc/jail.conf

#	jail-info.sh list (jail_name) [ (jail_name) ] ...
#
#		list all parameters of jail(s) (jail_name) in /etc/jail.conf

#	jail-info.sh (jail_name) param [ param ] ...
#
#		show value of param in jail (jail_name)'s config

#	(jail_name) can be  ALL  in any of the above, in which
#	case it will be expanded to the list of jails in /etc/rc.conf
#	variable jail_list.

# -n           Do not show variable names.  This option is useful for
#                   setting shell variables.


while getopts "dnh?" opt
do
	case "$opt" in
	d)
		debug=1
		;;
	n)
		vals_only=1		# show values only, not variable names
		;;
	h|\?)
		usage
		exit 1
		;;
	*)
		printf 'unknown option: %s\n' "$opt"
	esac
done

shift $(($OPTIND-1))


jail_info() {

local executable="/root/bin/"

	[[ -x "$executable"jail ]] || unset executable

	"$executable"jail -e ''		# NUL-delimited fields, with an empty,
								# NUL-delimited line between jails
} # jail_info


jail_pop_array() {

#	$1 is NAME of associative array to return
#	$2 is NAME of indexed NUL-terminated array to read from

#	The first jail described in $2 will be popped off and returned
#	as associative array $1.

#	CALLER MUST declare $1 associative PRIOR to calling

local -n jp="$1" jls="$2"
local ind elem var val

	for var in ${!jp[@]}
	do
		unset jp["$var"]
	done

# keep a list of the keys in the order they were added

	jp["_keys"]=" "

	for ind in ${!jls[@]}
	do

		elem="${jls[ind]}"
		unset jls[$ind]

#[[ $debug ]] && printf '%2d:	%s\n' $ind "$elem"

		[[ "$elem" ]] || break

		var="${elem%%=*}"		# variable name
		val="${elem#$var}"		# remainder is value
		val="${val#=}"			# strip leading '=' off value, if present

#[[ $debug ]] && [[ "$val" =~ exec\..* ]] && printf 'jp[%s]="%s"\n' "$var" "$val"
		jp["_keys"]+="$var "
		jp["$var"]="$val"

	done

	[[ "$ind" ]]		# return true if ind is set

} # jail_pop_array


jail_print() {

# generate a bash script on standard output that will print the caller's
# choice of variables from the jail array passed by name in $1

# variables to print are in $2 .. $N

local -n jail
local jail_array sp v val

	jail="$1"			# pointer to the jail info array
	jail_array="$1"		# name    of the jail info array

	shift

	echo "${jail[@]@A}"
	echo "unset vals_only"
	echo "${vals_only@A}"

# This perhaps would be a little clearer if converted to a
# printf (sigh, but then we'd have nested printf's ....)

# Even so, why not eventually move toward just printing
# the values ourself, straight from the jail array?

	cat << EOF
sp=
for v in ${@}
do
	val="\${$jail_array["\$v"]}"
	val="\${val@A}"
	val="\${val#val=}"
	if [[ \$vals_only ]]
	then
		printf '%s%s' "\$sp" "\${val}"
		sp=' '
	else
		printf '%s%s\n' "\$v" "\${val:+=\${val}}"
	fi
done
if [[ \$vals_only ]]
then
	printf '\n'
fi
EOF

} # jail_print


#==================================================
#
#			M A I N
#
#==================================================


main() {

# $1 is "list", "all" or jail name
# $2 .. $N is jail names for "list"
#          or jail parameters or "all" for "all" or jail name

local jails params cmd j_info j sp nm v

declare -a jails params

	if [[ "${1,,}" == "list" ]]				# possibly followed by jail names
	then									# to list, *if* they are defined

		cmd="list"
		shift
		[[ $# -eq 0 ]] || jails=( "$@" )	# empty array means list all defined names

	else									# otherwise $1 is "all" or a jail name

		cmd="show"			
		[[ "${1,,}" == "all" ]] || jails=( "$1" )	# empty array means all jails
		shift
		[[ "${1,,}" == "all" ]] || params=( "$@" )	# empty array means all parameters

	fi

# jail_info returns NUL-delimited lines, one field per line
# lines start with <variablename>.  empty NUL-terminated line
# after each jail.

	readarray -d "" j_info < <(jail_info)

	declare -A j						# Must declare associative BEFORE call

	while jail_pop_array j j_info		# pop one jail off of j_info into j
	do {

		if [[ "$cmd" == "list" ]]
		then

			if ( [[ ${#jails[@]} -eq 0 ]] ||
					egrep -Fqx "${j["name"]}" < <(printf '%s\n' "${jails[@]}") )
			then
				printf '%s' "${sp:+$'\t'}" "${j["name"]}"
				sp=$'\n'
			fi

		elif [[ "$cmd" == "show" ]]
		then

			if ( [[ ${#jails[@]} -eq 0 ]] ||
					egrep -Fqx "${j["name"]}" < <(printf '%s\n' "${jails[@]}") )
			then

				j_nm="${j["name"]}"

# many variables are simply declared, and not assigned any value.
# Should we assign them a value of 1?

				if [[ ${#params[@]} -gt 0 ]]
				then
					set -- ${params[@]}
				else
					set -- ${j["_keys"]}
				fi

				jail_print "j" "$@" | bash
#				bash -s -- "$@" < bash.in.$j_nm > bash.out.$j_nm 2>&1
#				cat bash.out.$j_nm

			fi

		fi

	} done	# while jail_pop_array

	printf '%s' "$sp"		# print newline if needed

} # main



main "$@"
