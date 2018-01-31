
export TMPFS_DIR=/dev/shm
[ -d "$TMPFS_DIR" ] || TMPFS_DIR=/tmp

function gpid() {
	local PID
	PID=$$ && [ ! -z "$1" ] && PID="$1"
	cat /proc/$PID/stat | sed 's/([^)]*)/X/g' | awk '{print $5}'
}
export -f gpid

function gcat() {
	# get cat?	great cat?	Not sure what I'm going for with this name.
	if [ -e "$1" ]; then
		cat "$1"
	else
		# Try to decompress, first, and if it can't, forget the compression.
		curl -k -s -L "$1" | gzip -dc 2>/dev/null || curl -k -s -L "$1"
	fi
}
export -f gcat

function xcolor() {
	TO="\e[$1m"
	FROM='\e[0m' && [ ! -z "$2" ] && FROM="$2"
	xargs -I@ printf "$TO%s$FROM\n" "@"
}
export -f xcolor

function uid() {
	# WARNING: This leaves junk sitting around /dev/shm or wherever.
	TMP=$TMPFS_DIR/uid.$$
	[ -f $TMP ] || echo 0 > $TMP
	let V=`cat $TMP | head -1`
	echo `expr $V + 1` > $TMP
	echo $$.$V
}
export -f uid

function arglines() {
	while [ $# -gt 0 ]; do
		echo "$1"
	done
}
export -f arglines

function kget() {
	F="$1"
	K="$2"
	V=`grep "^$K:" "$F"` || return 1
	echo "$V" | sed 's/^[^:]*://'
}
export -f kget

function kset() {
	F="$1"
	K="$2"
	V="$3"
	if grep -q "^${K}:" "$F"; then
		sed -i'' "s#^${K}:.*#${K}:${V}#" "$F"
	else
		echo "${K}:${V}" >> "$F"
	fi
}
export -f kset

function vsetadd() {
	F="$1"
	TMP=$TMPFS_DIR/vsetadd.$$.$RANDOM
	cp "$F" $TMP
	shift ; arglines >> $TMP
	cat $TMP | sort -u > "$F"
	[ -f $TMP ] && rm $TMP
}
export -f vsetadd

function vsetremove() {
	F="$1"
	TMP=$TMPFS_DIR/vsetremove.$$.$RANDOM
	shift
	comm -23 "$F" <(arglines | sort -u) > $TMP
	mv $TMP "$F"
	[ -f $TMP ] && rm $TMP
}
export -f vsetremove

export toss_PID=$$
function toss() {
	TMP=$TMPFS_DIR/toss.$toss_PID
	touch $TMP
	while [ $# -gt 0 ]; do
		echo "$1" >> $TMP
		shift
	done
}
export -f toss

function dispose() {
	TMP=$TMPFS_DIR/toss.$toss_PID
	# WARNING: Name uniqueness not absolute, and can't count on uid, yet.
	TMP2=$TMPFS_DIR/tmp.$toss_PID.$RANDOM
	GREP=.
	[ -z "$1" ] || GREP="$1"
	grep "$GREP" $TMP | while read line; do
		if [ -e "$line" -a ! -d "$line" ]; then
			echo removing $line 1>&2
			rm "$line"
		else
			echo $line
		fi
	done > $TMP2
	[ -f $TMP ] && cp $TMP2 $TMP
	[ -f $TMP2 ] && rm $TMP2
}
export -f dispose

export throttle_FIFO=/tmp/throttle.`uid`.fifo && toss $throttle_FIFO
function throttle() {
	#echo throttle: $@ 1>&2
	K=$1
	LIMIT="$2"
	export TF=$TMPFS_DIR/throttle.$K
	export PF=$TMPFS_DIR/throttle-pids.$K
	toss $TF $PF
	#echo throttle: $@ 1>&2
	
	[ -e $TF ] || touch $TF #&& chattr +S $TF
	[ -e $PF ] || touch $PF #&& chattr +S $PF
	[ -z `kget $TF count` ] && kset $TF count 0
	[ -e $throttle_FIFO ] || mkfifo $throttle_FIFO #&& chattr +S $throttle_FIFO
	
	#echo K: $K, LIMIT: $LIMIT 1>&2
	
	while read LINE; do
		export LINE
	(
		PID=$BASHPID
		COUNT=`kget $TF count`
		kset $PF prior $PID
		kset $TF count `expr $COUNT + 1`
		COUNT=`kget $TF count`
		#echo PID: $PID, COUNT: $COUNT 1>&2
		
		if [ "$LIMIT" -lt "$COUNT" ]; then
			echo pausing $PID: $LIMIT vs $COUNT 1>&2
			# This is what freezes(?) the process
			read < $throttle_FIFO
			#echo continuing $PID 1>&2
			kset $TF count $(expr `kget $TF count` - 1) SIGUSR1
		fi
		
		echo $LINE
	) &
	wait
	#echo done that line $LINE
	done
}
export -f throttle

function unthrottle() {
	K="$1"
	PF=$TMPFS_DIR/throttle-pids.$K
	PID=`kget $PF prior`
	
	#echo unthrottle K:$K PF:$PF PID:$PID 1>&2
	#kill -SIGUSR1 $PID
	echo $PID > $throttle_FIFO
}
export -f unthrottle

function cleanup() {
	echo cleanup

	# NOTE: Not sure if putting this before the kill subrpocesses will cause
	#	 problems, since some of the files to clean may belong to child processes.
	toss $CLEANUP_FILES
	dispose

	kill -TERM -$toss_PID
}
export -f cleanup

# A few scraping functions?
function elattr() {
	[ -z "$2" ] || {
		echo "$2" | sed "s/.*$1=\"//; s/\".*//"
		return 0
	}
	[ -z "$2" ] && {
		while read line; do
			elattr "$1" "$line"
		done
	}
}
export -f elattr

function sortmap() {
	R=""
	while [ "$1" != '-x' ]; do
		R="$R $1"
		shift
	done
	[ "$1" = '-x' ] && shift
	T=/tmp/`uid`
	mkfifo "$T"
	# tee acts against sortmap's stdin
	paste -d'|' <(
		tee "$T" | bash -c "$@";
	) "$T" | \
		sort $R -t'|' -k1 | \
		sed "s/^[^|]*|//"
	[ -e "$T" ] && rm "$T"
}
export -f sortmap

function abspath() {
	# Normally, this would be a job for readlink -f, but OS X doesn't support its
	# absolute path behavior.
	if [ -d "$1/" ]; then (
		# File is a directory.
		cd "$1"
		pwd -P # '-P' takes care of symlink expansion
	); else
		
		F=`echo "$1" | sed 's#//*$##'`
		if [ -L "$F" -o -h "$F" ]; then
			# File itself is a symlink.
			abspath "$(stat $1 -c %N | sed 's/.* -> .//; s/.$//')"
			return $?
		else
			# File is not a symlink.
			DNAME=`dirname "$1"`
			NAME=`echo "$1" | sed "s#^$DNAME//*##"`
			echo `abspath $DNAME`/$NAME
		fi
	fi
}
export -f abspath


