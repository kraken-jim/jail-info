#!/usr/bin/env bash

set -e

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


#==================================================
#
#	Extract jail info from /etc/jail.conf files
#
#==================================================

usage() {

cat << EOF
usage:

	jail-info.sh -[hn] list [ (jail_name) [ (jail_name) ... ] ]

		If no jail_name is given, print a tab-delimited list of jails
		known to jail(8).  Otherwise, print jail_name for each 
		jail_name specified that is known to jail(8).  If at least
		one of the jails is found, return success.  If none of the
		jails can be found, return failure.  This can be used to
		test whether a jail is defined:

			jail-info.sh list myjail || echo "myjail was not found"

	jail-info.sh [ (jail_name) | all ] [ all | param [ param ... ] ]

		show value of param in the configuration for jail
		(jail_name); if "all" is used as a jail name, show the
		selected params for all defined jails.  If "all" is used as 
		the first parameter name, print all parameters for the
		selected jail(s).  If none of the parameters is defined, 
		return failure, else return success.

	OPTIONS
		-h	Show this help message.

 		-n	Do not show variable names.  Show values only, all on one
			line.  For each jail, in sequence, the selected parameter 
			values are printed with with bash-style quoting, space-
			separated, in the order specified on the command line.  
			This option is useful for setting shell variables, for
			example:

				jail-info.sh -n all linux.osname name path |
				while IFS= read -r line; do 
					eval set -- "${line}"
					printf 'jail "%s" is running "%s", ' "$2" "$1"
					printf 'jail root is "%s"\n' "$3"
				done

EOF

} # usage


jail_info() {

	jail -e ''		# NUL-delimited fields, with an empty,
					# NUL-delimited line between jails
} # jail_info


jail_pop_array() {

#	args are call-by-reference, not call-by-value

#	$1 is NAME of associative array to return
#	$2 is NAME of indexed NUL-terminated array to read from

#	The first jail described in $2 will be popped off and returned
#	as associative array $1.

#	CALLER MUST declare $1 associative PRIOR to calling

local -n jpop="$1" jails="$2"
local ind elem var val

	for var in ${!jpop[@]}
	do
		unset jpop["$var"]
	done

# keep a list of the keys in the order they were added

	jpop["_keys"]=" "

	for ind in ${!jails[@]}
	do

		elem="${jails[ind]}"
		unset jails[$ind]

#[[ $debug ]] && printf >&2 '%2d:	%s\n' $ind "$elem"

		[[ "$elem" ]] || break

		var="${elem%%=*}"		# variable name
		val="${elem#$var}"		# remainder is value
		val="${val#=}"			# strip leading '=' off value, if present

		jpop["_keys"]+="$var "	# append key to ordered list of keys

		jpop["$var"]="$val"		# set value in associative array

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

local rc=1 jails params cmd j_array one_jail sp

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

# jail_info returns NUL-delimited lines, one field per line.
# lines start with <variablename>.  one empty NUL-terminated
# line after each jail.

	readarray -d "" j_array < <(jail_info) || return
	[[ ${#j_array[@]} -gt 0 ]] || return

	declare -A one_jail						# Must declare associative BEFORE call

	while jail_pop_array one_jail j_array	# pop one jail off of j_array into j
	do {

		if [[ "$cmd" == "list" ]]
		then

			if ( [[ ${#jails[@]} -eq 0 ]] ||
					egrep -Fqx "${one_jail["name"]}" < <(printf '%s\n' "${jails[@]}") )
			then
				printf '%s' "${sp:+$'\t'}" "${one_jail["name"]}"
				rc=0
				sp=$'\n'	# we'll need a newline eventually
			fi

		elif [[ "$cmd" == "show" ]]
		then

			if ( [[ ${#jails[@]} -eq 0 ]] ||
					egrep -Fqx "${one_jail["name"]}" < <(printf '%s\n' "${jails[@]}") )
			then

# some parameters are simply declared, but not assigned any value.

				if [[ ${#params[@]} -gt 0 ]]	# if specific params are given,
				then
					set -- ${params[@]}			# then use only those.
				else
					set -- ${one_jail["_keys"]}	# Otherwise show all params
				fi

				jail_print "one_jail" "$@" | bash
				rc=$?

			fi

		fi

	} done	# while jail_pop_array

	printf '%s' "$sp"		# print newline if needed

	return $rc

} # main


main "$@"
