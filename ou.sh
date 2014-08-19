#!/bin/bash
################################################################################
#
#	SYSTEM NAME:	Oracle RAC Operation Utility
#						Copyright (c) 2013 t.ashihara All rights reserved.
#
#	HISTORY:
#	DATE		AUTHOR		COMMENTS
#	2013.07.03	t.ashihara	Create v0.1.
#
################################################################################

# get environment variables.
if [ -f ./ou.config ]; then
	. ./ou.config
fi

#-------------------------------------------------------------------------------
#	check user.
if [ ${_CHECK_USER} != '' ]; then
	if [ `whoami` != ${_CHECK_USER} ]; then
		echo "### Please run as user '${_CHECK_USER}'."
		exit 1
	fi
fi
#-------------------------------------------------------------------------------

# get shell info.
DIR_NAME=`dirname ${0}` 				# get path name.	(ex./home/user/test.sh ->	/home/user	)
SHL_NAME=`basename ${0}`				# get shell name.	(ex./home/user/test.sh ->	test.sh 	)
FIL_NAME=${SHL_NAME%.*} 				# get file name.	(ex./home/user/test.sh ->	test		)
EXT_NAME=${SHL_NAME##*.}				# get extension.	(ex./home/user/test.sh ->	sh			)

RETURN_CODE=0

STATUS_BUFFER=${TEMP}/${SHL_NAME}.$$.`uuidgen -t`.tempx
DISPLAY_BUFFER=${TEMP}/${SHL_NAME}.$$.`uuidgen -t`.temp

CLUSTER_STATUS_MODE=${_STS_MODE_ORIGINAL}

# for all

	BLANKS=$(for i in $(seq 1 ${_STS_NAME_MAX_LENGTH}); do echo -n " "; done)

# for status
	# get node no and name. (ex. olsnodes -s -t)
	NODE_NOS=("?" $(olsnodes -n | awk '{print $2 " " $1 }' | sort | awk '{ print $1 }' | while read NO; do echo -n ${NO}" "; done))
	NODE_NAMES=("?" $(olsnodes -n | awk '{print $2 " " $1 }' | sort | awk '{ print $2 }' | while read NODE; do echo -n ${NODE}" "; done))

	# define description.
	STS_DESC[0]=" - ora.gsd is typically offline. you must enable if you plan to use an rac 9i db."
	STS_DESC[1]=" - legend:"
	STS_DESC[2]="\t${_STS_INACTIVE}name${_ESC_RS} : node is not active."
	STS_DESC[3]="\t${_STS_ONOFF}no${_ESC_RS}   : target/status = ONline /OFFline"
	STS_DESC[4]="\t${_STS_OFFOFF}no${_ESC_RS}   : target/status = OFFline/OFFline"
	STS_DESC[5]="\t${_STS_OTHERS}no${_ESC_RS}   : target/status = others (enter 'S' to see the details.)"

	# define category code.
	CATEGORY_LOCAL="Local  "
	CATEGORY_CLUSTER="Cluster"

	# define node status code.
	NODE_STS_ONON=0
	NODE_STS_ONOFF=1
	NODE_STS_OFFOFF=2
	NODE_STS_OTHER=9

#-------------------------------------------------------------------------------
ctrlC()
{
	rm -f ${STATUS_BUFFER}
	rm -f ${DISPLAY_BUFFER}
	exit 1

}

#-------------------------------------------------------------------------------
putTitle()
{
	ACTIVEVERSION=`crsctl query crs activeversion | awk '{ print $9}'`
	ACTIVEVERSION=${ACTIVEVERSION//[/${_ESC_BD}}
	ACTIVEVERSION=${ACTIVEVERSION//]/${_ESC_RS}}
	echo -n "" > ${DISPLAY_BUFFER};
	echo	"============================================================"		>> ${DISPLAY_BUFFER}
	echo	"   Oracle RAC Operation Utility ${_VERSION}"						>> ${DISPLAY_BUFFER}
	echo	"       Copyright (c) 2013 t.ashihara All rights reserved." 		>> ${DISPLAY_BUFFER}
	echo	"       I don't compensate any damage caused by using this."		>> ${DISPLAY_BUFFER}
	echo	"       Check the code yourself, please use at your own risk."		>> ${DISPLAY_BUFFER}
	echo	"============================================================"		>> ${DISPLAY_BUFFER}
	echo -e "  Cluster ${ACTIVEVERSION} Status\t\t`date "+%Y-%m-%d %H:%M:%S"`"	>> ${DISPLAY_BUFFER}
	echo	"------------------------------------------------------------"		>> ${DISPLAY_BUFFER}
	return 0
}


#-------------------------------------------------------------------------------
showClusterStatus()
{

	##########################
	#	nodestatus
	##########################
	echo -n "NODE: "	>> ${DISPLAY_BUFFER}
	for ((i=1; i<${#NODE_NOS[@]}; ++i)) do
		echo -n ${NODE_NOS[${i}]}"="		>> ${DISPLAY_BUFFER}
		NODE_NAME=${NODE_NAMES[${i}]}
		if [ "$(olsnodes -s ${NODE_NAME} | awk '{print $2}')" = "Active" ]; then
			echo -e -n "${NODE_NAME} "								>> ${DISPLAY_BUFFER}
		else
			echo -e -n "${_STS_INACTIVE}${NODE_NAME}${_ESC_RS} "	>> ${DISPLAY_BUFFER}
		fi
	done
	echo "" >> ${DISPLAY_BUFFER}
	echo "" >> ${DISPLAY_BUFFER}

	##########################
	#	cluster status
	##########################
	DISPLAY_CATEGORY=""
	DISPLAY_NAME=""
	unset DISPLAY_STATUS

	crsctl status resource -t | \
		sed -e "s|[ ]\+| |g"	> ${STATUS_BUFFER}
	while read LINE; do
		case "${LINE:0:4}" in
			"----" | "NAME")						;;
			"Loca") CATEGORY=${CATEGORY_LOCAL}		;;
			"Clus") CATEGORY=${CATEGORY_CLUSTER}	;;
			"ora.") RESOURCE_NAME=${LINE}			;;
			*)
					unset ARRAY;
					ARRAY=(${LINE})

					if [ "${CATEGORY}" = "${CATEGORY_LOCAL}" ]; then
						# Local Resources
						NAME="${RESOURCE_NAME}"
						BASE_INDEX=0
					else
						# Cluster Resources

							# ignore the 'STATE_DETAILS' that wraps.
							if [ -z "$(echo ${ARRAY[0]} | sed -e 's|[0-9]||g')" ]; then :; else continue; fi

						NAME="${RESOURCE_NAME}-(${ARRAY[0]})"
						BASE_INDEX=1
					fi
					TARGET=${ARRAY[$((${BASE_INDEX}))]}
					STATUS=${ARRAY[$((${BASE_INDEX}+1))]}
					NODE=${ARRAY[$((${BASE_INDEX}+2))]}
					DETAIL="$(for ((i=$((${BASE_INDEX}+3)); i<${#ARRAY[@]}; ++i)) do echo -n ${ARRAY[${i}]}" "; done)"

					if [ "${DISPLAY_NAME}" != "${NAME}" ]; then
						if [ ${#DISPLAY_NAME} -gt 0 ]; then
							echo -e -n "${DISPLAY_CATEGORY} ${BLANKS:0:$((${#BLANKS}-${#DISPLAY_NAME}))}${DISPLAY_NAME} "	>> ${DISPLAY_BUFFER}
							for ((i=0; i<${#NODE_NOS[@]}; ++i)); do
								if [ -z "${DISPLAY_STATUS[${i}]}" ]; then
									echo -e -n "$(echo ${NODE_NOS[${i}]} | sed -e 's|.| |g') "	>> ${DISPLAY_BUFFER}
								else
									case "${DISPLAY_STATUS[${i}]}" in
										"${NODE_STS_ONON}") 	STS=""				;;
										"${NODE_STS_ONOFF}")	STS=${_STS_ONOFF}	;;
										"${NODE_STS_OFFOFF}")	STS=${_STS_OFFOFF}	;;
										*)						STS=${_STS_OTHERS}	;;
									esac
									echo -e -n "$(echo ${STS}${NODE_NOS[${i}]}${_ESC_RS}) " >> ${DISPLAY_BUFFER}
								fi
							done
							echo "" >> ${DISPLAY_BUFFER}
						fi
						DISPLAY_CATEGORY=${CATEGORY}
						DISPLAY_NAME=${NAME}
						unset DISPLAY_STATUS
					fi

					MATCH_INDEX=0
					for ((i=1; i<${#NODE_NAMES[@]}; ++i)) do
						if [ "${NODE}" = "${NODE_NAMES[${i}]}" ]; then
							MATCH_INDEX=${i}
							break
						fi
					done

					DISPLAY_STATUS[${MATCH_INDEX}]=${NODE_STS_OTHER}
					case "${TARGET}" in
						"ONLINE")
									case "${STATUS}" in
										"ONLINE")	DISPLAY_STATUS[${MATCH_INDEX}]=${NODE_STS_ONON} 	;;
										"OFFLINE")	DISPLAY_STATUS[${MATCH_INDEX}]=${NODE_STS_ONOFF}	;;
									esac
									;;
						"OFFLINE")
									case "${STATUS}" in
										"OFFLINE")	DISPLAY_STATUS[${MATCH_INDEX}]=${NODE_STS_OFFOFF}	;;
									esac
									;;
					esac
					;;
		esac
	done < ${STATUS_BUFFER}

	echo -e -n "${DISPLAY_CATEGORY} ${BLANKS:0:$((${#BLANKS}-${#DISPLAY_NAME}))}${DISPLAY_NAME} "	>> ${DISPLAY_BUFFER}
	for ((i=0; i<${#NODE_NOS[@]}; ++i)); do
		if [ -z "${DISPLAY_STATUS[${i}]}" ]; then
			echo -e -n "$(echo ${NODE_NOS[${i}]} | sed -e 's|.| |g') "	>> ${DISPLAY_BUFFER}
		else
			case "${DISPLAY_STATUS[${i}]}" in
				"${NODE_STS_ONON}") 	STS=""				;;
				"${NODE_STS_ONOFF}")	STS=${_STS_ONOFF}	;;
				"${NODE_STS_OFFOFF}")	STS=${_STS_OFFOFF}	;;
				*)						STS=${_STS_OTHERS}	;;
			esac
			echo -e -n "$(echo ${STS}${NODE_NOS[${i}]}${_ESC_RS}) " >> ${DISPLAY_BUFFER}
		fi
	done
	echo "" >> ${DISPLAY_BUFFER}

	echo "------------------------------------------------------------" 	>> ${DISPLAY_BUFFER}
	echo	"* description" 		>> ${DISPLAY_BUFFER}
	`for ((i=0; i<${#STS_DESC[@]}; ++i)); do echo -e "${STS_DESC[${i}]}" >> ${DISPLAY_BUFFER}; done`

	return 0
}

#-------------------------------------------------------------------------------
selectItem()
{
	CODE=(0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z)
	ARGS=($@)
	ITEM_NAME=${ARGS[0]}
	FORCE=${ARGS[1]}
	OPTION=${ARGS[2]}
	for ((i=0; i<$((${#ARGS[@]}-3)); ++i)) do
		ITEMS[${i}]=${ARGS[$((${i}+3))]}
	done
	LIST="$(for ((i=${FORCE}; i<${#ITEMS[@]}; ++i)) do echo -n ${CODE[${i}]}":"${ITEMS[${i}]}" "; done)"
	LIST=`echo "${LIST}" | sed -e "s|0:- ||g"`
	while :; do
		read -p "[?] Select ${ITEM_NAME}. ( ${LIST}) > " -n 1 ANS
		ANS=`echo ${ANS} | tr "a-z" "A-Z"`
		for ((i=${FORCE}; i<${#CODE[@]}; ++i)) do
			if [ "${ANS}" = "${CODE[${i}]}" ]; then
				if [ ${FORCE} -eq 0 ] && [ "${ANS}" -eq "0" ]; then
					break 2
				elif [ -n "${ITEMS[${i}]}" ]; then
					echo ${OPTION}" "${ITEMS[${i}]}
					break 2
				else
					echo -n -e "\xd" >&2
				fi
			fi
		done
		echo -n -e "\xd" >&2
	done
	echo "" >&2
}

#-------------------------------------------------------------------------------
selectDb()
{
	FORCE=${1}
	ITEMS=("none" $(crsctl status resource -w "TYPE = ora.database.type" | grep "NAME=" | grep ".db$" | sed -e "s|NAME=ora.||g;s|.db$||g" | sort))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "db" "${FORCE}" "-d" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectStartOption()
{
	FORCE=${1}
	ITEMS=("none" "open" "mount" "nomount")
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "start-option" "${FORCE}" "-o" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectStopOption()
{
	FORCE=${1}
	ITEMS=("none" "normal" "transactional" "immediate" "abort")
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "stop-option" "${FORCE}" "-o" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectNode()
{
	FORCE=${1}
	ITEMS=("none" $(for ((i=1; i<${#NODE_NAMES[@]}; ++i)) do echo -n ${NODE_NAMES[${i}]}" "; done))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "node" "${FORCE}" "-n" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectListener()
{
	FORCE=${1}
	ITEMS=("none" $(crsctl status resource -w "TYPE = ora.listener.type" | grep "NAME=" | grep ".lsnr$" | sed -e "s|NAME=ora.||g;s|.lsnr$||g" | sort))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "listener" "${FORCE}" "-l" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectVip()
{
	FORCE=${1}
	ITEMS=("none" $(crsctl status resource -w "TYPE = ora.cluster_vip_net1.type" | grep "NAME=" | grep ".vip$" | sed -e "s|NAME=ora.||g;s|.vip$||g" | sort))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "vip" "${FORCE}" "-i" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectScanListener()
{
	FORCE=${1}
	ITEMS=("none" $(crsctl status resource -w "TYPE = ora.scan_listener.type" | grep "NAME=" | grep ".lsnr$" | sed -e "s|NAME=ora.||g;s|.lsnr$||g" | sort))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "scan-listener" "${FORCE}" "-i" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectScanVip()
{
	FORCE=${1}
	ITEMS=("none" $(crsctl status resource -w "TYPE = ora.scan_vip.type" | grep "NAME=" | grep ".vip$" | sed -e "s|NAME=ora.||g;s|.vip$||g" | sort))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "scan-vip" "${FORCE}" "-i" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectDiskGroup()
{
	FORCE=${1}
	ITEMS=("none" $(crsctl status resource -w "TYPE = ora.diskgroup.type" | grep "NAME=" | grep ".dg$" | sed -e "s|NAME=ora.||g;s|.dg$||g" | sort))
	if [ ${FORCE} -gt 0 ]; then
		FORCE=1
		ITEMS[0]="-"
	fi
	selectItem "diskgroup" "${FORCE}" "-g" "${ITEMS[@]}"
}

#-------------------------------------------------------------------------------
selectGSD()
{
	while :; do
		read -p "[?] GSD only ? (y/n) > " -n 1 ANS
		case "${ANS}" in
			"y" | "Y")	echo "-g";				break;	;;
			"n" | "N")							break;	;;
			*)			echo -n -e "\xd" >&2			;;
		esac
	done
	echo "" >&2
}

#-------------------------------------------------------------------------------
selectForce()
{
	while :; do
		read -p "[?] Force ? (y/n) > " -n 1 ANS
		case "${ANS}" in
			"y" | "Y")	echo "-f";				break;	;;
			"n" | "N")							break;	;;
			*)			echo -n -e "\xd" >&2			;;
		esac
	done
	echo "" >&2
}

#-------------------------------------------------------------------------------
operation()
{
	echo ""
	echo "------------------------------------------------------------"
	echo	""
	echo	"target:"
	echo -e "\t0 CANCEL        5 scan_listener A cvu"
	echo -e "\t1 database      6 scan_vip      B gns"
	echo -e "\t2 instance      7 asm           C oc4j"
	echo -e "\t3 listener      8 diskgroup     D ons"
	echo -e "\t4 vip           9 nodeapps"
	echo	""
	while :; do
		read -p "[?] Select target. (0-C) > " -n 1 TARGET
		case "${TARGET}" in
			"0")		return 0						;;
			"1")		TARGET="database";		break	;;
			"2")		TARGET="instance";		break	;;
			"3")		TARGET="listener";		break	;;
			"4")		TARGET="vip";			break	;;
			"5")		TARGET="scan_listener";	break	;;
			"6")		TARGET="scan_vip";		break	;;
			"7")		TARGET="asm";			break	;;
			"8")		TARGET="diskgroup";		break	;;
			"9")		TARGET="nodeapps";		break	;;
			"a" | "A")	TARGET="cvu";			break	;;
			"b" | "B")	TARGET="gns";			break	;;
			"c" | "C")	TARGET="oc4j";			break	;;
			"d" | "D")	TARGET="ons";			break	;;
#			home
#			service
#			filesystem
			*)			echo -n -e "\xd"				;;
		esac
	done
	echo ""

	while :; do
		read -p "[?] Select operation. ( 0:cancel 1:start 2:stop ) > " -n 1 STARTSTOP
		case "${STARTSTOP}" in
			"0")	return 0					;;
			"1")	STARTSTOP="start";	break	;;
			"2")	STARTSTOP="stop";	break	;;
			*)		echo -n -e "\xd" 			;;
		esac
	done
	echo ""

	case "${STARTSTOP}" in
		"start")
			case "${TARGET}" in
				"database")			COMMAND="srvctl start database `selectDb 1` `selectStartOption 0`";					;;
				"instance")			COMMAND="srvctl start instance `selectDb 1` `selectNode 1` `selectStartOption 0`";	;;
				"listener")			COMMAND="srvctl start listener `selectListener 0`";									;;
				"vip")				COMMAND="srvctl start vip `selectVip 1` -v";										;;
				"scan_listener")	COMMAND="srvctl start scan_listener `selectScanListener 0`";						;;
				"scan_vip")			COMMAND="srvctl start scan `selectScanVip 0`";										;;
				"asm")				COMMAND="srvctl start asm `selectNode 0` `selectStartOption 0`";					;;
				"diskgroup")		COMMAND="srvctl start diskgroup `selectDiskGroup 1` `selectNode 0`";				;;
				"nodeapps")			COMMAND="srvctl start nodeapps `selectNode 0` `selectGSD 0` -v";					;;
				"cvu")				COMMAND="srvctl start cvu `selectNode 0`";											;;
				"gns")				COMMAND="srvctl start gns `selectNode 0`";											;;
				"oc4j")				COMMAND="srvctl start oc4j -v";														;;
				"ons")				COMMAND="srvctl start ons -v";														;;
				*)					echo "### happen logical error."; exit 1;											;;
			esac
			;;
		"stop")
			case "${TARGET}" in
				"database")			COMMAND="srvctl stop database `selectDb 1` `selectStopOption 0` `selectForce 0`";					;;
				"instance")			COMMAND="srvctl stop instance `selectDb 1` `selectNode 1` `selectStopOption 0` `selectForce 0`";	;;
				"listener")			COMMAND="srvctl stop listener `selectListener 0` `selectForce 0`";									;;
				"vip")				COMMAND="srvctl stop vip `selectVip 1` -v";															;;
				"scan_listener")	COMMAND="srvctl stop scan_listener `selectScanListener 0` `selectForce 0`";							;;
				"scan_vip")			COMMAND="srvctl stop scan `selectScanVip 0` `selectForce 0`";										;;
				"asm")				COMMAND="srvctl stop asm `selectNode 0` `selectStartOption 0` `selectForce 0`";						;;
				"diskgroup")		COMMAND="srvctl stop diskgroup `selectDiskGroup 1` `selectNode 0` `selectForce 0`";					;;
				"nodeapps")			COMMAND="srvctl stop nodeapps `selectNode 0` `selectForce 0` `selectGSD 0` -v";						;;
				"cvu")				COMMAND="srvctl stop cvu `selectForce 0`";															;;
				"gns")				COMMAND="srvctl stop gns `selectNode 0` `selectForce 0` -v";										;;
				"oc4j")				COMMAND="srvctl stop oc4j `selectForce 0` -v";														;;
				"ons")				COMMAND="srvctl stop ons -v";																		;;
				*)					echo "### happen logical error."; exit 1;															;;
			esac
			;;
		*)
			echo "### happen logical error."
			exit 1
			;;
	esac

	echo ""
	COMMAND=`echo ${COMMAND} | sed -e "s|[ ]\+| |g"`
	echo -e "command = ${_ESC_BD}${COMMAND}${_ESC_RS}"
	while :; do
		read -p "[?] Are you sure you want to run the above command ? (y/n) > " -n 1 ANS
		case "${ANS}" in
			"y" | "Y")
						echo ""
						echo "............................................................"
						${COMMAND}
						echo "............................................................"
						echo ""
						read -p "Enter any key to continue. " -n 1 ANS
						break
						;;
			"n" | "N")
						break
						;;
			*)
						echo -n -e "\xd"
						;;
		esac
	done
}

#-------------------------------------------------------------------------------
clusterOperation()
{
	REFRESH_INTERVAL=${_STS_REFRESH_INTERVAL}

	while :; do

		putTitle;

		case ${CLUSTER_STATUS_MODE} in
			${_STS_MODE_ORIGINAL})	# original
				showClusterStatus
				;;

			${_STS_MODE_CRSCTL})	# crsctl status resource -t
				crsctl status resource -t	>> ${DISPLAY_BUFFER}
				;;

			${_STS_MODE_CRSSTAT})	# crs_stat -t
				echo -e "${_ESC_BD}[!] this information using the command 'crs_stat'"	>> ${DISPLAY_BUFFER}
				echo -e "that was deprecated in Oracle Clusterware 11gR2."				>> ${DISPLAY_BUFFER}
				echo -e "so, please do not trust this information.${_ESC_RS}"			>> ${DISPLAY_BUFFER}
				echo ""	>> ${DISPLAY_BUFFER}
				crs_stat -t	>> ${DISPLAY_BUFFER}
				;;
			*)
				;;
		esac

		echo "------------------------------------------------------------" 	>> ${DISPLAY_BUFFER}
		echo "" >> ${DISPLAY_BUFFER}

		clear
		cat ${DISPLAY_BUFFER}
		echo -n -e "[?] ${_ESC_US}1-9${_ESC_RS}:refresh interval=${REFRESH_INTERVAL}sec ${_ESC_US}S${_ESC_RS}:switch ${_ESC_US}O${_ESC_RS}:operation ${_ESC_US}Q${_ESC_RS}:quit > "
		read -t ${REFRESH_INTERVAL} -n 1 ANS

		case "${ANS}" in
			[1-9])		# set refresh interval
						REFRESH_INTERVAL=${ANS}
						;;
			"s" | "S")	# switch
						CLUSTER_STATUS_MODE=$((${CLUSTER_STATUS_MODE}+1))
						if [ ${CLUSTER_STATUS_MODE} -gt ${_STS_MODE_MAX} ]; then
							CLUSTER_STATUS_MODE=0
						fi
						;;
			"o" | "O")	# start or stop
						operation
						;;
			"q" | "Q")	# quit
						echo ""
						rm -f ${STATUS_BUFFER}	>> /dev/null
						rm -f ${DISPLAY_BUFFER} >> /dev/null
						return 0
						;;
		esac
	done
	return 1
}

################################################################################
#	main routine

#	trap CTRL+C to remove temp files.
trap 'ctrlC' INT

clusterOperation

echo ""
exit 0
