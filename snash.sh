#
# Snash
#
# Snake in bash, main file
#
# @author Timon Ole Ensel
# https://github.com/forgottosave/snash
#
# @license MIT
#

#!/bin/bash

##### GLOBAL VARs
VERSION=1.4
# game fixed
SPF=170 # milliseconds per frame
Y_MAX=16
X_MAX=32
DRAW_INITIAL_BOARD=true
MODE=5
INIT_SIZE=3 # initial snake size
APL_PLUS=10
APL_MINUS=-10
# game state
DIR="" # player direction
POS=$(($Y_MAX / 2 * $X_MAX + $X_MAX / 2))
APP="" # apple position
ACN=0 # apple existing counter
ARR=1 # apple respawn rate (value>=1, 1=highest)
SCORE=0 # game score
LEVEL=1 # current level
NEXT_LEVEL=1000 # score needed for next level up
LEVEL_MSG_UNTIL=0 # timestamp (ns) until which the level-up message is shown
# colors
RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
YLW='\033[0;33m'
# characters
PLR="#"
NOO="."
APL="O"
# additional files needed
THIS_DIR=$(dirname "$0")
F_STARTFRAMES="$THIS_DIR/resources/.startupframes"
F_HELPTEXT="$THIS_DIR/resources/.helptext"
F_SCORES="$HOME/.snash_scores"
# fifo array for positions
declare -a FIFO
declare -a DIG # countdowns (in frames) for apples still being digested


##### ARGUMENT PARSING
setup_fullscreen() {
	Y_MAX=$(($(tput lines) - 2)) #16
	X_MAX=$(($(tput cols)  - 1)) #32
	POS=$(($Y_MAX / 2 * $X_MAX + $X_MAX / 2))
	#move cursor to bottom of screen without printing new lines
	printf "\033[${Y_MAX}B"
}
# pretty-print best score, longest snake and the last 5 runs
# this method is AI-generated because... yeah
show_scores() {
	if [[ ! -s "$F_SCORES" ]]; then
		echo "No scores yet. Go play!"
		return
	fi
	awk -F' // ' -v G="$GRN" -v Y="$YLW" -v N='\033[0m' '
	{
		s = $2; sub(/^Score: /, "", s);  s += 0
		l = $3; sub(/^Length: /, "", l); l += 0
		m = $4; sub(/^Mode: /, "", m);   gsub(/ +$/, "", m)
		d = $5; sub(/^Death: /, "", d)
		row[NR] = sprintf("%-4s %7d  %6d  %s", $1, s, l, d)
		if (NR == 1 || s > bs) { bs = s; bsi = NR }
		if (NR == 1 || l > bl) { bl = l; bli = NR }
	}
	END {
		hdr = sprintf("%-4s %7s  %6s  %s", "Ver", "Score", "Length", "Death")
		print G "=== SNASH SCORES ===" N "\n"
		print Y "Highest score" N;  print "  " hdr; print "  " row[bsi] "\n"
		print Y "Longest snake" N;  print "  " hdr; print "  " row[bli] "\n"
		print Y "Last 5 runs (newest first)" N; print "  " hdr
		for (i = NR; i > NR - 5 && i >= 1; i--) print "  " row[i]
	}' "$F_SCORES" | printf "%b\n" "$(cat)"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h|--help)
		printf "%b" "$(cat "$F_HELPTEXT")"
	    echo ""
		exit 0
	;;
	-v|--version)
		echo "snash v$VERSION"
	    exit 0
	;;
	-s|--scores)
	    #cat "$F_SCORES"
	    show_scores
		exit 0
	;;
	-f|--fullscreen)
		setup_fullscreen
	;;
	-t|--in-terminal)
		DRAW_INITIAL_BOARD=false
		setup_fullscreen
	;;
	-easy)
		MODE='EASY   (0) '
	    SPF=200
	    INIT_SIZE=2
	    APL_MINUS=0
	;;
	-medium) #Default difficulty
	    MODE='MEDIUM (5) '
	;;
	-hard)
		MODE='HARD  (10) '
	    SPF=100
	    INIT_SIZE=4
	    APL_MINUS=-40
	;;
	-d)
		shift
		if ! [[ $1 =~ ^[0-9]+$ ]] || [[ $1 -le 0 ]]; then
			echo "Difficulty must be a positive number."
			exit 1
		fi
		# change game difficulty
		MODE="$1"
		SPF=200
		INIT_SIZE=2
		APL_MINUS=0
		SPF=$((2 * "$SPF" / "$MODE" + 50))
		[[ $SPF -le 10 ]] && SPF=10
		[[ $SPF -ge 200 ]] && SPF=200
		INIT_SIZE=$(("$MODE" / 4 + "$INIT_SIZE"))
		APL_MINUS=$(("$APL_MINUS" - "$MODE" * 2))
	;;
	esac
	shift
done # while


##### METHODS
# game end
stop_game() { # $1=end_string
	printf "\r\033[K"
	printf "\033[5D\033[s\033[1A\033[K$1\n"
	printf "Scored ${GRN}<<<\033[0m $SCORE ${GRN}>>>\033[0m\n"
	printf "and reached length: ${#FIFO[@]}\n"
	touch "$F_SCORES"
	echo "$VERSION // Score: $SCORE // Length: ${#FIFO[@]} // Mode: $MODE // Death: $1" >> $F_SCORES
	exit 0
}
# define interrupt action
interrupt() {
	stop_game "Game interrupted by user."
}
trap interrupt INT
# draw one point on screen
draw() { # $1=position $2=character
	x=$(pos_to_x "$1")
    y=$(pos_to_y "$1")
    # print new pos
    printf "\033[1D\033[s\033[${y}A\033[${x}C$2\033[u"
}
draw_det() { # $1=y $2=x $3=character
	printf "\033[1D\033[s\033[$1A\033[$2C$2\033[u"
}
# own collision
# @return 0 if dead, 1 if alive
player_dead() {
	#echo "Score: $SCORE -- Death: head ${POS} found in snake ${FIFO[@]}" >log
	[[ " ${FIFO[*]} " =~ " ${POS} " ]] && return 0 || return 1
}
# keyboard input to player direction
update_pos() { # $1 = user input
	old_pos=$POS
	case $DIR in
	w|W|k|K)
		POS=$(($POS + $X_MAX));;
	a|A|h|H)
        POS=$(($POS - 1));;
	s|S|j|J)
        POS=$(($POS - $X_MAX));;
	d|D|l|L)
        POS=$(($POS + 1));;
	*)
		printf "\033[1A\033[K"
        echo "frame=$var, ---PAUSED---, SCORE=$SCORE"
	;;
	esac
	# check game bounds
	old_x=$(pos_to_x "$old_pos")
    old_y=$(pos_to_y "$old_pos")
	new_x=$(pos_to_x "$POS")
    new_y=$(pos_to_y "$POS")
	if (($new_y < 2)) || (($new_y > ($Y_MAX + 1))) || (! ((old_y == new_y)) && ! ((old_x == new_x))) ; then
		stop_game "Game Over (hit wall)"
	fi
}
# updates apple spawning & despawning
update_apple() { # $1=current_frame
	ACN=$(($ACN + 1))
	# delete apple if existing time too long
	if (($ACN > 100)) && ! [[ $APP == "" ]]; then
		ACN=0
		draw $APP "${NOO}"
		APP=""
		SCORE=$(($SCORE + $APL_MINUS))
	# yellow apple if close to delete
	elif (($ACN > 80)) && ! [[ $APP == "" ]]; then
		draw $APP "${YLW}${APL}"
	fi
	if (($1 % $ARR)) || ! [[ $APP == "" ]]; then
		return
	fi
	# spawn apple
	ACN=0
	APP_SPAWN_X=$((RANDOM % (X_MAX - 1) + 1))
	APP_SPAWN_Y=$((RANDOM % Y_MAX + 2))
	APP=$(((APP_SPAWN_Y - 1) * X_MAX + APP_SPAWN_X))
	if [[ " ${FIFO[*]} " =~ " ${APP} " ]]; then
		APP=""
	else
		draw $APP "${GRN}${APL}"
	fi
}
# player position
pos_to_x() {
	ret=$(($1 % $X_MAX))
	echo "$ret"
}
pos_to_y() {
	ret=$(($1 / $X_MAX + 1))
	echo "$ret"
}
# increase player score
increase_score()  {
	SCORE=$(($SCORE + $APL_PLUS * (${#DIG[@]} + 1))) # multi-apple digest = more points :)
	#SCORE=$(($SCORE + $APL_PLUS))
	# level up every 1000 points
	while (($SCORE >= $NEXT_LEVEL)); do
		LEVEL=$(($LEVEL + 1))
		NEXT_LEVEL=$(($NEXT_LEVEL + 1000))
		# level effects (more speed and more bad-apple-penalty)
		SPF=$(($SPF - 5))
		[[ $SPF -le 10 ]] && SPF=10 # keep the same lower bound as -d
		APL_MINUS=$(($APL_MINUS * $LEVEL))
		# set how long level up text should be shown
		LEVEL_MSG_UNTIL=$(($(date +%s%N) + 6000000000))
	done
}
# show level-up / combo text on the line below the board
show_combo() {
	printf "\r\033[K" # clear the line
	if ((${#DIG[@]} > 1)); then
		printf "      ${YLW}<< %dx combo >>\033[0m" "${#DIG[@]}"
		printf "\033[u"
	fi
	# check if level text should be shown
	local now
	now=$(date +%s%N)
	if (((now / 800000000) % 2 == 0)); then
	if (($(date +%s%N) < LEVEL_MSG_UNTIL)); then
		printf "\r\033[K"
		printf "      ${YLW}*** LEVEL UP! - LEVEL %d ***\033[0m" "$LEVEL"
	fi
	fi
}
# updates player for next frame
update_player() {
	# tick digestion timers, drop apples that reached the tail
	local alive=()
	for t in "${DIG[@]}"; do
		(( t > 1 )) && alive+=($((t - 1)))
	done
	DIG=("${alive[@]}")
	# check for apple
	if [[ "$APP" -eq "$POS" ]]; then
		APP=""
		FIFO+=("$POS")
		increase_score
		DIG+=("${#FIFO[@]}") # this apple needs ~length frames to reach the tail
		draw $POS "${BLU}${PLR}"
	else
		draw $POS "${GRN}${PLR}"
	fi
	# push new pos
	FIFO+=("$POS")
	#draw $POS "${GRN}${PLR}"
	# pop tail
	tail_pos=${FIFO[0]}
	FIFO=("${FIFO[@]:1}")
	draw $tail_pos "${RED}${NOO}"
}
# startup sequence
startup() {
	# draw fancy start screen stuff
	for i in {00..64}; do
		grep -A 5 "$i" $F_STARTFRAMES
		sleep .02
		printf "\033[6A"
	done
	# create player
	for i in $(seq 1 $INIT_SIZE); do
	    FIFO+=("$POS")
	done
	# start
    echo "Press any key to start..."
    read -n 1 input
	printf "\033[1D\033[1A"
    DIR='w'
	# finally, draw gamepanel only if inital board is enabled
	if ! $DRAW_INITIAL_BOARD; then
		# move cursor to bottom of screen
		printf "\033[${Y_MAX}B"
		return
	fi
	for row in $(seq 0 $Y_MAX); do
    	line=""
    	for col in $(seq 0 $(($X_MAX - 2))); do
    	    line="${line}${NOO}"
    	done
    	echo " ${line} "
	done
}
# calculates and loads one frame
# @return 0 if dead, 1 if alive after frame
loadframe() {
	printf "\033[1D"
    # print score
    printf "\033[1A\033[K"
    echo -e "${GRN} <<<  \033[0m${SCORE}${GRN}  >>>\033[0m"
    #echo "frame=$var, input=$input, DIR=$DIR, SCORE=$SCORE"
	# frame
    printf "\033[s"
    update_pos
    if player_dead && [[ ! $DIR == "" ]]; then
         return 0
	fi
    update_player
    update_apple "$var"
    show_combo
    printf "\033[u"
    # catch user input
    read -n 1 -s -t .02 input
    if [[ $? -gt 128 ]]; then
		return 1
	fi
    DIR="$input";
	return 1
}

##### GAME
startup
# game loop
starttime=`date +%s%N`
var=0
while true; do
	newtime=`date +%s%N`
	nextframe=$(($starttime + $SPF * 1000000))
	if [[ "$newtime" -gt "$nextframe" ]]; then
		starttime=`date +%s%N`
		if loadframe; then
			break
		fi
	fi
	#sleep 1
	var=$((var + 1))
done
# game ending
stop_game "Game Over (don't eat yourself)"



