
function decwait() {
	KEY="$1"
	COUNT=1  && [ ! -z "$2" ] && COUNT="$2"
	SLEEP=.1 && [ ! -z "$3" ] && SLEEP="$3"
	export COUNT
	export SLEEP
	export PARPID=$$
	[ -z "$COUNT" ] && exit 1
	(
		export TMP=/dev/shm/decwait.$KEY
		export DEBT=/dev/shm/decwait.debt.$KEY
		# WARNING: If debt has been created for this key, but decwait never has a
		#   chance to be called, the debt file will remain.
		function clean() {
			[ -f "$TMP" ] && rm "$TMP"
			[ -f "$DEBT" ] && rm "$DEBT"
		}
		trap clean EXIT
		echo $COUNT > $TMP
		if [ -f "$DEBT" ]; then
			# If decrementing has begun before decwait is run, pay back the debt...
			cat "$DEBT" | while read x; do
				[ x = '-' ] && dec $KEY
				[ x = '+' ] && inc $KEY
			done
			rm "$DEBT" # ... and be done with it.
		fi
		while true; do
			# Break if parent process no longer exists.
			[ -d /proc/$PARPID ] || break
			let A=(`head -1 $TMP`)
			# WARNING: Imprecise, allowing for cases where decrementing exceeds max
			#   expected value.  Good enough, though, without exception handling.
			# Break once decwait file value reaches (or drops below) zero.
			[ $A -le 0 ] && break
			sleep $SLEEP
		done
	) &
	CHILD=$!
	wait $CHILD
}

function _decop() {
	OP="$1"
	KEY="$2"
	TMP=/dev/shm/decwait.$KEY
	DEBT=/dev/shm/decwait.debt.$KEY
	[ ! -f $TMP ] && {
		echo -- - >> $DEBT
		return 0
	}
	let A=`head -1 $TMP`
	echo `expr "$A" $OP 1` > $TMP
}
function dec() {
	_decop '-' $@
}
function inc() {
	_decop '+' $@
}


