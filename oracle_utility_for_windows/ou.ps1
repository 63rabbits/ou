################################################################################
#
#	SYSTEM NAME:	Oracle RAC Operation Utility for Windows
#						Copyright (c) 2013 t.ashihara All rights reserved.
#
#	HISTORY:
#	DATE		AUTHOR		COMMENTS
#	2013.07.14	t.ashihara	Create v0.1.
#
################################################################################

#	read .ini file.
Get-Content .\ou.ini | Foreach-Object {
	$def, $comment = $_.split('#', 2)
	$name, $value = $def.split('=', 2)
	if (($name.length -gt 0) -and ($value.length -gt 0)) {
		$name	= $name.trim()
		$value	= $value.trim()
		Invoke-Expression "`$$name='$value'"
	}
}

#	set locale.
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $_CULTURE
[System.Threading.Thread]::CurrentThread.Currentculture = $_CULTURE

#	my environment
$MY_PATH = split-path $myinvocation.mycommand.path -parent
$MY_NAME = $myinvocation.mycommand.name

$STATUS_BUFFER = $env:tmp + "\" + $MY_NAME + "." + [string][guid]::newguid() + ".tmp"
$DISPLAY_BUFFER = $env:tmp + "\" + $MY_NAME + "." + [string][guid]::newguid() + ".tmp"
$SO_BUFFER = $env:tmp + "\" + $MY_NAME + "." + [string][guid]::newguid() + ".tmp"

$CLUSTER_STATUS_MODE = [int]${_STS_MODE_ORIGINAL}
$REFRESH_INTERVAL = ${_STS_REFRESH_INTERVAL}

# for status
	# get node no and name. (ex. olsnodes -s -t)
	$NODE_NOS	 = @("?")
	$NODE_NOS	+= @($((olsnodes -n) -replace "[`t ]+"," " | foreach-object { $1, $2 = $_.split(' ', 2); write-output "${2} ${1}" } | sort-object | foreach-object { $1, $2 = $_.split(' ', 2); write-output ${1} } ))
	$NODE_NAMES  = @("?")
	$NODE_NAMES += @($((olsnodes -n) -replace "[`t ]+"," " | foreach-object { $1, $2 = $_.split(' ', 2); write-output "${2} ${1}" } | sort-object | foreach-object { $1, $2 = $_.split(' ', 2); write-output ${2} } ))

	# define category code.
	$CATEGORY_LOCAL 	= "Local  "
	$CATEGORY_CLUSTER	= "Cluster"

	# define node status code.
	$NODE_STS_UNKNOWN	= -1
	$NODE_STS_ONON		= 0
	$NODE_STS_ONOFF 	= 1
	$NODE_STS_OFFOFF	= 2
	$NODE_STS_OTHER 	= 9

#-------------------------------------------------------------------------------
function startTimer()
{
	return get-date
}

#-------------------------------------------------------------------------------
function checkTimer([int]$INTERVAL, [datetime]$START_TIME)
{
	if (${INTERVAL} -eq $NULL) { return $TRUE }
	if (${START_TIME} -eq $NULL) { return $TRUE }

	$TIME_SPAN = $(get-date) - ${START_TIME}
	$ELAPSE_TIME = [int][math]::truncate(${TIME_SPAN}.totalseconds)
	if (${ELAPSE_TIME} -ge ${INTERVAL}) {
		return $TRUE
	}
	else {
		return $FALSE
	}
}

#-------------------------------------------------------------------------------
function putTitle()
{
	$ACTIVEVERSION = $(crsctl query crs activeversion)
	$DUMMY, $ACTIVEVERSION = ${ACTIVEVERSION}.split('[', 2)
	$ACTIVEVERSION, $DUMMY = ${ACTIVEVERSION}.split(']', 2)
	"============================================================"					| out-file ${DISPLAY_BUFFER}
	"   Oracle RAC Operation Utility ${_VERSION} for Windows"						| out-file ${DISPLAY_BUFFER} -append
	"       Copyright (c) 2013 t.ashihara All rights reserved." 					| out-file ${DISPLAY_BUFFER} -append
	"       I don't compensate any damage caused by using this."					| out-file ${DISPLAY_BUFFER} -append
	"       Check the code yourself, please use at your own risk."					| out-file ${DISPLAY_BUFFER} -append
	"============================================================"					| out-file ${DISPLAY_BUFFER} -append
	"  Cluster ${ACTIVEVERSION} Status`t$(get-date -format 'yyyy/MM/dd HH:mm:ss')"	| out-file ${DISPLAY_BUFFER} -append
	"------------------------------------------------------------"					| out-file ${DISPLAY_BUFFER} -append
	return 0
}

#-------------------------------------------------------------------------------
function showClusterStatus()
{
	##########################
	#	nodestatus
	##########################
	write-host -n "NODE: "
	for ($i=1; $i -lt ${NODE_NOS}.length; $i++) {
		write-host -n ${NODE_NOS}[${i}]
		write-host -n "="
		$STATUS = $((olsnodes -s ${NODE_NAMES}[${i}]) -replace "[`t ]+"," ").split()
		if (${STATUS}[1] -eq "Active") {
			write-host -n ${NODE_NAMES}[${i}]
		}
		else {
			write-host -n -f white -b red ${NODE_NAMES}[${i}]
		}
		write-host -n " "
	}
	write-host ""
	write-host ""

	##########################
	#	cluster status
	##########################
	$DISPLAY_CATEGORY	= ""
	$DISPLAY_NAME		= ""
	$DISPLAY_STATUS 	= @(${NODE_STS_UNKNOWN}) * ${NODE_NOS}.length

	crsctl status resource -t | foreach-object { $($_.trim()) -replace "[`t ]+"," " } | out-file ${STATUS_BUFFER}

	get-content ${STATUS_BUFFER} |
		foreach-object {
			$ARRAY = $_.split()
			switch (${ARRAY}[0]) {
				{$_.startswith("----")} {	break										}
				"NAME"					{	break										}
				"Local" 				{	$CATEGORY = ${CATEGORY_LOCAL};		break	}
				"Cluster"				{	$CATEGORY = ${CATEGORY_CLUSTER};	break	}
				{$_.startswith("ora.")} {	$RESOURCE_NAME = $_ ;				break	}
				default {

					if ("${CATEGORY}" -eq "${CATEGORY_LOCAL}") {
						# Local Resources
						$NAME=${RESOURCE_NAME}
						$BASE_INDEX = 0
					}
					else {
						# Cluster Resources

							# ignore the 'STATE_DETAILS' that wraps.
							if ($(${ARRAY}[0] -replace "[0-9]","").length -gt 0) { continue }

						$NAME= "${RESOURCE_NAME}-(" + ${ARRAY}[0] + ")"
						$BASE_INDEX = 1
					}
					$TARGET = ${ARRAY}[$(${BASE_INDEX})]
					$STATUS = ${ARRAY}[$(${BASE_INDEX} + 1)]
					$NODE	= ${ARRAY}[$(${BASE_INDEX} + 2)]
					$DETAIL = $(for ($i=$(${BASE_INDEX} + 3); $i -lt ${ARRAY}.count; $i++) { write-output ${ARRAY}[${i}] })

					if (${DISPLAY_NAME} -ne ${NAME}) {
						if (${DISPLAY_NAME}.length -gt 0) {
							write-host -n "${DISPLAY_CATEGORY} $(${DISPLAY_NAME}.padleft(${_STS_NAME_MAX_LENGTH})) "
							for ($i=0; $i -lt ${NODE_NOS}.length; $i++) {
								if (${DISPLAY_STATUS}[${i}] -eq ${NODE_STS_UNKNOWN}) {
									write-host -n $(${NODE_NOS}[${i}] -replace "."," ")
								}
								else {
									switch (${DISPLAY_STATUS}[${i}]) {
										${NODE_STS_ONON}	{	write-host -n						${NODE_NOS}[${i}];	break	}
										${NODE_STS_ONOFF}	{	write-host -n -f black -b yellow	${NODE_NOS}[${i}];	break	}
										${NODE_STS_OFFOFF}	{	write-host -n -f white -b red		${NODE_NOS}[${i}];	break	}
										default 			{	write-host -n -f white -b blue		${NODE_NOS}[${i}];	break	}
									}
								}
								write-host -n " "
							}
							write-host " "
						}
						$DISPLAY_CATEGORY	= ${CATEGORY}
						$DISPLAY_NAME		= ${NAME}
						$DISPLAY_STATUS 	= @(${NODE_STS_UNKNOWN}) * ${NODE_NOS}.length
					}

					$MATCH_INDEX = 0
					for ($i=1; $i -lt ${NODE_NAMES}.length; $i++) {
						if (${NODE} -eq ${NODE_NAMES}[${i}]) {
							$MATCH_INDEX = ${i}
							break
						}
					}

					$DISPLAY_STATUS[${MATCH_INDEX}] = ${NODE_STS_OTHER}
					switch (${TARGET}) {
						"ONLINE"	{
										switch (${STATUS}) {
											"ONLINE"	{	$DISPLAY_STATUS[${MATCH_INDEX}] = ${NODE_STS_ONON}; 	break	}
											"OFFLINE"	{	$DISPLAY_STATUS[${MATCH_INDEX}] = ${NODE_STS_ONOFF};	break	}
										}
										break
									}
						"OFFLINE"	{
										switch (${STATUS}) {
											"OFFLINE"	{	$DISPLAY_STATUS[${MATCH_INDEX}] = ${NODE_STS_OFFOFF};	break	}
										}
										break
									}
					}

				}
			}
		}

	write-host -n "${DISPLAY_CATEGORY} $(${DISPLAY_NAME}.padleft(${_STS_NAME_MAX_LENGTH})) "
	for ($i=0; $i -lt ${NODE_NOS}.length; $i++) {
		if (${DISPLAY_STATUS}[${i}] -eq ${NODE_STS_UNKNOWN}) {
			write-host -n $(${NODE_NOS}[${i}] -replace "."," ")
		}
		else {
			switch (${DISPLAY_STATUS}[${i}]) {
				${NODE_STS_ONON}	{	write-host -n						${NODE_NOS}[${i}];	break	}
				${NODE_STS_ONOFF}	{	write-host -n -f black -b yellow	${NODE_NOS}[${i}];	break	}
				${NODE_STS_OFFOFF}	{	write-host -n -f white -b red		${NODE_NOS}[${i}];	break	}
				default 			{	write-host -n -f white -b blue		${NODE_NOS}[${i}];	break	}
			}
		}
		write-host -n " "
	}
	write-host " "

	write-host	"------------------------------------------------------------"
	write-host	"* description"
	write-host	" - ora.gsd is typically offline. you must enable if you plan to use an rac 9i db."
	write-host	" - legend:"

	write-host -n "`t"; write-host -n -f white -b red	 "name";	write-host " : node is not active."
	write-host -n "`t"; write-host -n -f black -b yellow "no";		write-host "   : target/status = ONline /OFFline"
	write-host -n "`t"; write-host -n -f white -b red	 "no";		write-host "   : target/status = OFFline/OFFline"
	write-host -n "`t"; write-host -n -f white -b blue	 "no";		write-host "   : target/status = others (enter 'S' to see the details.)"

	return 0
}

#-------------------------------------------------------------------------------
function selectItem()
{
	$PARAMS = ${ARGS}[0].split()

	$CODE 		= @("0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z")
	$ITEM_NAME 	= ${PARAMS}[0]
	$FORCE 		= [int]${PARAMS}[1]
	$OPTION 	= ${PARAMS}[2]
	for ($i=0; $i -lt (${PARAMS}.length - 3); $i++) {
		$ITEMS[${i}] = ${PARAMS}[$(${i}+3)]
	}
	$LIST = $(for ($i=${FORCE}; $i -lt ${ITEMS}.length; $i++) { write-output "$(${CODE}[${i}]):$(${ITEMS}[${i}])" })
	$LIST = ${LIST} -replace "[\t ]+"," "

	:LOOP
	while ($TRUE) {
		write-host -n "[?] Select ${ITEM_NAME}. ( ${LIST} ) > "
        $ANS = [Console]::ReadKey($FALSE)
		for ($i=${FORCE}; $i -lt ${CODE}.length; $i++) {
			if (${ANS}.KeyChar -eq ${CODE}[${i}]) {
				if ((${FORCE} -eq 0 ) -and (${ANS}.KeyChar -eq "0")) {
					break LOOP
				}
				elseif (${ITEMS}[${i}] -ne $NULL) {
					write-output "${OPTION} $(${ITEMS}[${i}])"
					break LOOP
				}
			}
		}
		write-host -n "`r"
	}
	write-host ""
}

#-------------------------------------------------------------------------------
function selectDb()
{
	$FORCE  = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS += @($($(crsctl status resource -w "TYPE = ora.database.type" | select-string -pattern "NAME=" | select-string -pattern ".db$") -replace "NAME=ora.","" -replace ".db$","" | sort-object))
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "db ${FORCE} -d ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectStartOption()
{
	$FORCE = ${ARGS}[0]
	$ITEMS = @("none","open","mount","nomount")
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "start-option ${FORCE} -o ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectStopOption()
{
	$FORCE = ${ARGS}[0]
	$ITEMS = @("none","normal","transactional","immediate","abort")
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "stop-option ${FORCE} -o ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectNode()
{
	$FORCE  = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS += @($(for ($i=1; $i -lt ${NODE_NAMES}.length; $i++) { write-output ${NODE_NAMES}[${i}]}))
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "node ${FORCE} -n ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectListener()
{
	$FORCE = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS += @($(crsctl status resource -w "TYPE = ora.listener.type" | select-string -pattern "NAME=" | select-string -pattern ".lsnr$") -replace "NAME=ora.","" -replace ".lsnr$","" | sort-object)
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "listener ${FORCE} -l ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectVip()
{
	$FORCE  = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS  += @($(crsctl status resource -w "TYPE = ora.cluster_vip_net1.type" | select-string -pattern "NAME=" | select-string -pattern ".vip$") -replace "NAME=ora.","" -replace ".vip$","" | sort-object)
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "vip ${FORCE} -i ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectScanListener()
{
	$FORCE  = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS += @($(crsctl status resource -w "TYPE = ora.scan_listener.type" | select-string -pattern "NAME=" | select-string -pattern ".lsnr$") -replace "NAME=ora.","" -replace ".lsnr$","" | sort-object)
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "scan-listener ${FORCE} -i ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectScanVip()
{
	$FORCE  = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS += @($(crsctl status resource -w "TYPE = ora.scan_vip.type" | select-string -pattern "NAME=" | select-string -pattern ".vip$") -replace "NAME=ora.","" -replace ".vip$","" | sort-object)
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "scan-vip ${FORCE} -i ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectDiskGroup()
{
	$FORCE  = ${ARGS}[0]
	$ITEMS  = @("none")
	$ITEMS += @($(crsctl status resource -w "TYPE = ora.diskgroup.type" | select-string -pattern "NAME=" | select-string -pattern ".dg$") -replace "NAME=ora.","" -replace ".dg$","" | sort-object)
	if (${FORCE} -gt 0) {
		$FORCE = 1
		$ITEMS[0] = "-"
	}
	selectItem "diskgroup ${FORCE} -g ${ITEMS}"
}

#-------------------------------------------------------------------------------
function selectGSD()
{
	:LOOP
	while ($TRUE) {
		write-host -n "[?] GSD only ? (y/n) > "
        $ANS = [Console]::ReadKey($FALSE)
		switch (${ANS}.KeyChar) {
			"Y"		{	write-output "-g";	break LOOP	}
			"N"		{						break LOOP	}
			default	{	write-host -n "`b"				}
		}
	}
	write-host ""
}

#-------------------------------------------------------------------------------
function selectForce()
{
	:LOOP
	while ($TRUE) {
		write-host -n "[?] Force ? (y/n) > "
        $ANS = [Console]::ReadKey($FALSE)
		switch (${ANS}.KeyChar) {
			"Y"		{	write-output "-f";	break LOOP	}
			"N"		{						break LOOP	}
			default	{	write-host -n "`b"				}
		}
	}
	write-host ""
}

#-------------------------------------------------------------------------------
function operation()
{
	write-host ""
	write-host "------------------------------------------------------------"
	write-host	""
	write-host	"target:"
	write-host "`t0 database      5 scan_vip      A gns"
	write-host "`t1 instance      6 asm           B oc4j"
	write-host "`t2 listener      7 diskgroup     D ons"
	write-host "`t3 vip           8 nodeapps"
	write-host "`t4 scan_listener 9 cvu           C CANCEL"
	write-host	""
	:TARGET
	while ($TRUE) {
		write-host -n "[?] Select target. (0-D) > "
        $CODE = [Console]::ReadKey($FALSE)
		switch (${CODE}.KeyChar) {
			"0" 	{	$TARGET = "database";		break TARGET	}
			"1" 	{	$TARGET = "instance";		break TARGET	}
			"2" 	{	$TARGET = "listener";		break TARGET	}
			"3" 	{	$TARGET = "vip";			break TARGET	}
			"4" 	{	$TARGET = "scan_listener";	break TARGET	}
			"5" 	{	$TARGET = "scan_vip";		break TARGET	}
			"6" 	{	$TARGET = "asm";			break TARGET	}
			"7" 	{	$TARGET = "diskgroup";		break TARGET	}
			"8" 	{	$TARGET = "nodeapps";		break TARGET	}
			"9" 	{	$TARGET = "cvu";			break TARGET	}
			"A" 	{	$TARGET = "gns";			break TARGET	}
			"B" 	{	$TARGET = "oc4j";			break TARGET	}
			"C" 	{	return 0									}
			"D" 	{	$TARGET = "ons";			break TARGET	}
#			home
#			service
#			filesystem
			default {	write-host -n "`r"; 		break			}
		}
	}
	write-host ""

	:STARTSTOP
	while ($TRUE) {
		write-host -n "[?] Select operation. ( 0:cancel 1:start 2:stop ) > "
		$CODE = [Console]::ReadKey($FALSE)
		switch (${CODE}.KeyChar) {
			"0" 	{	return 0								}
			"1" 	{	$STARTSTOP = "start";	break STARTSTOP	}
			"2" 	{	$STARTSTOP = "stop";	break STARTSTOP	}
			default {	write-host -n "`r";		break			}
		}
	}
	write-host ""

	switch (${STARTSTOP}) {
		"start" {
					switch (${TARGET}) {
						"database"		{	$ARGUMENT = "start database $(selectDb 1) $(selectStartOption 0)";					}
						"instance"		{	$ARGUMENT = "start instance $(selectDb 1) $(selectNode 1) $(selectStartOption 0)";	}
						"listener"		{	$ARGUMENT = "start listener $(selectListener 0)"; 									}
						"vip"			{	$ARGUMENT = "start vip $(selectVip 1) -v";											}
						"scan_listener" {	$ARGUMENT = "start scan_listener $(selectScanListener 0)";							}
						"scan_vip"		{	$ARGUMENT = "start scan $(selectScanVip 0)";										}
						"asm"			{	$ARGUMENT = "start asm $(selectNode 0) $(selectStartOption 0)";						}
						"diskgroup" 	{	$ARGUMENT = "start diskgroup $(selectDiskGroup 1) $(selectNode 0)";					}
						"nodeapps"		{	$ARGUMENT = "start nodeapps $(selectNode 0) $(selectGSD 0) -v";						}
						"cvu"			{	$ARGUMENT = "start cvu $(selectNode 0)";											}
						"gns"			{	$ARGUMENT = "start gns $(selectNode 0)";											}
						"oc4j"			{	$ARGUMENT = "start oc4j -v";														}
						"ons"			{	$ARGUMENT = "start ons -v";															}
						default 		{	write-host "### happen logical error."; start-sleep -s 5; exit 1;					}
					}
					break
				}
		"stop"	{
					switch (${TARGET}) {
						"database"		{	$ARGUMENT = "stop database $(selectDb 1) $(selectStopOption 0) $(selectForce 0)"; 					}
						"instance"		{	$ARGUMENT = "stop instance $(selectDb 1) $(selectNode 1) $(selectStopOption 0) $(selectForce 0)"; 	}
						"listener"		{	$ARGUMENT = "stop listener $(selectListener 0) $(selectForce 0)"; 									}
						"vip"			{	$ARGUMENT = "stop vip $(selectVip 1) -v"; 															}
						"scan_listener" {	$ARGUMENT = "stop scan_listener $(selectScanListener 0) $(selectForce 0)";							}
						"scan_vip"		{	$ARGUMENT = "stop scan $(selectScanVip 0) $(selectForce 0)";										}
						"asm"			{	$ARGUMENT = "stop asm $(selectNode 0) $(selectStartOption 0) $(selectForce 0)";						}
						"diskgroup" 	{	$ARGUMENT = "stop diskgroup $(selectDiskGroup 1) $(selectNode 0) $(selectForce 0)";					}
						"nodeapps"		{	$ARGUMENT = "stop nodeapps $(selectNode 0) $(selectForce 0) $(selectGSD 0) -v";						}
						"cvu"			{	$ARGUMENT = "stop cvu $(selectForce 0)";															}
						"gns"			{	$ARGUMENT = "stop gns $(selectNode 0) $(selectForce 0) -v";											}
						"oc4j"			{	$ARGUMENT = "stop oc4j $(selectForce 0) -v";														}
						"ons"			{	$ARGUMENT = "stop ons -v";																			}
						default 		{	write-host "### happen logical error."; start-sleep -s 5; exit 1;									}
					}
					break
				}
		default {
					write-host "### happen logical error."
					start-sleep -s 5
					exit 1;
				}
	}

	write-host ""
	write-host "command = srvctl $($(write-output ${ARGUMENT}) -replace "[`t ]+"," ")"
	:RUN
	while ($TRUE) {
		write-host -n "[?] Do you want to run the above command ? (y/n) > "
		$CODE = [Console]::ReadKey($FALSE)
		switch (${CODE}.KeyChar) {
			"Y" 	{
						write-host ""
						write-host "............................................................"
#						start-process srvctl -argument ${ARGUMENT} -wait -nonewwindow -redirectstandardoutput ${SO_BUFFER} -redirectstandarderror ${SE_BUFFER}
						start-process srvctl -argument ${ARGUMENT} -wait -nonewwindow -redirectstandardoutput ${SO_BUFFER}
						get-content ${SO_BUFFER} | write-host
						write-host "............................................................"
						write-host ""
						write-host -n "Enter any key to continue. "
						$CODE = [Console]::ReadKey($FALSE)
						break RUN
					}
			"N" 	{
						break RUN
					}
			default {
						write-host -n "`r"
					}
		}
	}

	return 0
}

#-------------------------------------------------------------------------------
function clusterOperation()
{
	$QUESTION = "[?] 1-9:refresh interval=@@@sec S:switch O:operation Q:quit > "
	$REFRESH = $true

	:LOOP
	while ($true) {
		$RESULT = checkTimer ${REFRESH_INTERVAL} ${START_TIME}
		if (${RESULT} -or ${REFRESH}) {
			$START_TIME = startTimer
			$REFRESH = $false

			$DUMMY = putTitle

			switch (${CLUSTER_STATUS_MODE}) {
				0		{	# original
							clear-host
							get-content ${DISPLAY_BUFFER} | write-host
							$DUMMY = showClusterStatus
							break
						}
				1		{	# crsctl status resource -t
							crsctl status resource -t								| out-file ${DISPLAY_BUFFER} -append
							clear-host
							get-content ${DISPLAY_BUFFER} | write-host
							break
						}
				2		{	# crs_stat -t
							"[!] this information using the command 'crs_stat -t'"	| out-file ${DISPLAY_BUFFER} -append
							"that was deprecated in Oracle Clusterware 11gR2."		| out-file ${DISPLAY_BUFFER} -append
							"so, please do not trust this information." 			| out-file ${DISPLAY_BUFFER} -append
							""														| out-file ${DISPLAY_BUFFER} -append
							crs_stat -t 											| out-file ${DISPLAY_BUFFER} -append
							clear-host
							get-content ${DISPLAY_BUFFER} | write-host
							break
						}
				default {
						}
			}

			write-host "------------------------------------------------------------"
			write-host -n "`n$(${QUESTION} -replace '@@@',${REFRESH_INTERVAL})"
			write-host -n -b darkgreen " `b"
		}

		if ([Console]::KeyAvailable) {

			$CODE = [Console]::ReadKey($FALSE)
			switch -r (${CODE}.KeyChar) {
				"[1-9]" {	# set refresh interval
							$REFRESH_INTERVAL = [string]${CODE}.KeyChar
							$START_TIME = startTimer
							break
						}
				default {
						}
			}
			switch (${CODE}.KeyChar) {
				"S" 	{	# switch
							$CLUSTER_STATUS_MODE = ${CLUSTER_STATUS_MODE} + 1
							if (${CLUSTER_STATUS_MODE} -gt ${_STS_MODE_MAX}) {
								$CLUSTER_STATUS_MODE = 0
							}
							break
						}
				"O" 	{	# start or stop
							$DUMMY = operation
							break
						}
				"Q" 	{	# quit
							remove-item ${STATUS_BUFFER}	2> $NULL
							remove-item ${DISPLAY_BUFFER}	2> $NULL
							remove-item ${SO_BUFFER}		2> $NULL
							break LOOP
						}
				default {
						}
			}
			$REFRESH = $true
			while ([Console]::KeyAvailable) { $IGNORE = [Console]::ReadKey($TRUE) }
		}
		start-sleep -m 100
	}

	return 0
}

################################################################################
#	main routine

#clear-host
$ui = (Get-Host).UI.RawUI
$ui.WindowTitle = $_TITLE

$IGNORE = clusterOperation

echo ""
write-output ""
write-host -f green " Goodbye !!"
sleep 1
exit 0
