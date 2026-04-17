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
# game fixed
SPF=160 # milliseconds per frame
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
KILL_COUNT=0 # number of enemies killed
EN_POS="" # enemy head position
EN_DIR="" # enemy current movement direction
EN_TARGET_SIZE=3 # enemy current target length
EN_GROWTH_SEC=15 # enemy grows by one every N seconds
EN_LAST_GROW_TS=0 # last enemy growth unix timestamp
# colors
RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
YLW='\033[0;33m'
# characters
PLR="#"
ENM="&"
NOO="."
APL="O"
# additional files needed
THIS_DIR=$(dirname "$0")
F_STARTFRAMES="$THIS_DIR/resources/.startupframes"
F_HELPTEXT="$THIS_DIR/resources/.helptext"
F_SCORES="$HOME/.snash_scores"
# fifo array for positions
declare -a FIFO
declare -a EN_FIFO


##### ARGUMENT PARSING
setup_fullscreen() {
	Y_MAX=$(($(tput lines) - 2)) #16
	X_MAX=$(($(tput cols)  - 1)) #32
	POS=$(($Y_MAX / 2 * $X_MAX + $X_MAX / 2))
	NOO=" "
	#move cursor to bottom of screen without printing new lines
	printf "\033[${Y_MAX}B"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h|--help)
		printf "%b" "$(cat "$F_HELPTEXT")"
	    echo ""
		exit 0
	;;
	-v|--version)
		echo "snash v1.2"
	    exit 0
	;;
	-s|--scores)
	    cat "$F_SCORES"
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
		SPF=130
	    INIT_SIZE=3
	    APL_MINUS=-10
	;;
	-hard)
		MODE='HARD  (10) '
	    SPF=90
	    INIT_SIZE=4
	    APL_MINUS=-20
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
	printf "\033[5D\033[s\033[1A\033[K$1  Score: $SCORE\033[u"
	touch "$F_SCORES"
	echo "$MODE // Death: $1 // Score: $SCORE" >> $F_SCORES
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
# check if position belongs to player body/head
is_on_player() { # $1=position
	[[ "$1" -eq "$POS" ]] && return 0
	[[ " ${FIFO[*]} " =~ " ${1} " ]] && return 0
	return 1
}
# check if position is within playable board
is_inside_board() { # $1=position
	x=$(pos_to_x "$1")
	y=$(pos_to_y "$1")
	(( x >= 1 )) && (( x <= (X_MAX - 1) )) && (( y >= 2 )) && (( y <= (Y_MAX + 1) ))
}
# enemy next position for one direction step
enemy_next_pos() { # $1=position $2=direction
	case "$2" in
	w) echo $(($1 + $X_MAX));;
	a) echo $(($1 - 1));;
	s) echo $(($1 - $X_MAX));;
	d) echo $(($1 + 1));;
	*) echo "$1";;
	esac
}
# wall + own body safety check for enemy
enemy_move_is_safe() { # $1=old_pos $2=new_pos
	old_x=$(pos_to_x "$1")
	old_y=$(pos_to_y "$1")
	new_x=$(pos_to_x "$2")
	new_y=$(pos_to_y "$2")
	if ((new_y < 2)) || ((new_y > (Y_MAX + 1))) || (! ((old_y == new_y)) && ! ((old_x == new_x))) ; then
		return 1
	fi
	[[ " ${EN_FIFO[*]} " =~ " ${2} " ]] && return 1
	return 0
}
# clear enemy drawing/state from board
clear_enemy() {
	for seg in "${EN_FIFO[@]}"; do
		draw "$seg" "${NOO}"
	done
	EN_FIFO=()
	EN_POS=""
	EN_DIR=""
}
# spawn enemy in random valid location with initial size 3
spawn_enemy() {
	for _ in $(seq 1 200); do
		head_x=$((RANDOM % (X_MAX - 1) + 1))
		head_y=$((RANDOM % Y_MAX + 2))
		head=$(((head_y - 1) * X_MAX + head_x))
		case $((RANDOM % 4)) in
		0) delta=$X_MAX;;
		1) delta=-1;;
		2) delta=-$X_MAX;;
		3) delta=1;;
		esac
		candidate=()
		ok=true
		for i in $(seq 2 -1 0); do
			seg=$((head - delta * i))
			if ! is_inside_board "$seg" || is_on_player "$seg" || [[ " ${candidate[*]} " =~ " ${seg} " ]]; then
				ok=false
				break
			fi
			candidate+=("$seg")
		done
		if $ok; then
			EN_FIFO=("${candidate[@]}")
			EN_POS="$head"
			case "$delta" in
			$X_MAX) EN_DIR="w";;
			-$X_MAX) EN_DIR="s";;
			1) EN_DIR="d";;
			-1) EN_DIR="a";;
			esac
			EN_TARGET_SIZE=3
			EN_LAST_GROW_TS=$(date +%s)
			for seg in "${EN_FIFO[@]}"; do
				draw "$seg" "${BLU}${ENM}"
			done
			return
		fi
	done
}
# remove dead enemy and create a new one
respawn_enemy() {
	KILL_COUNT=$((KILL_COUNT + 1))
	SCORE=$((SCORE + 50))
	clear_enemy
	spawn_enemy
}
# increase enemy length target every EN_GROWTH_SEC seconds
update_enemy_growth_target() {
	now_sec=$(date +%s)
	if ((EN_LAST_GROW_TS == 0)); then
		EN_LAST_GROW_TS=$now_sec
		return
	fi
	if ((now_sec - EN_LAST_GROW_TS >= EN_GROWTH_SEC)); then
		steps=$(((now_sec - EN_LAST_GROW_TS) / EN_GROWTH_SEC))
		EN_TARGET_SIZE=$((EN_TARGET_SIZE + steps))
		EN_LAST_GROW_TS=$((EN_LAST_GROW_TS + steps * EN_GROWTH_SEC))
	fi
}
# move enemy one frame using random safe direction preference
update_enemy() {
	[[ ${#EN_FIFO[@]} -eq 0 ]] && spawn_enemy
	[[ ${#EN_FIFO[@]} -eq 0 ]] && return

	update_enemy_growth_target
	all_dirs=("w" "a" "s" "d")
	safe_dirs=()
	safe_not_player=()
	for d in "${all_dirs[@]}"; do
		next=$(enemy_next_pos "$EN_POS" "$d")
		if enemy_move_is_safe "$EN_POS" "$next"; then
			safe_dirs+=("$d")
			if ! is_on_player "$next"; then
				safe_not_player+=("$d")
			fi
		fi
	done

	if [[ ${#safe_not_player[@]} -gt 0 ]]; then
		pool=("${safe_not_player[@]}")
		if [[ -n "$EN_DIR" ]]; then
			for d in "${safe_not_player[@]}"; do
				if [[ "$d" == "$EN_DIR" ]]; then
					# Add extra weight to keep moving straight when safe.
					pool+=("$d" "$d" "$d")
					break
				fi
			done
		fi
		chosen="${pool[$((RANDOM % ${#pool[@]}))]}"
	elif [[ ${#safe_dirs[@]} -gt 0 ]]; then
		pool=("${safe_dirs[@]}")
		if [[ -n "$EN_DIR" ]]; then
			for d in "${safe_dirs[@]}"; do
				if [[ "$d" == "$EN_DIR" ]]; then
					pool+=("$d" "$d" "$d")
					break
				fi
			done
		fi
		chosen="${pool[$((RANDOM % ${#pool[@]}))]}"
	else
		chosen="${all_dirs[$((RANDOM % ${#all_dirs[@]}))]}"
	fi

	next_pos=$(enemy_next_pos "$EN_POS" "$chosen")
	if ! enemy_move_is_safe "$EN_POS" "$next_pos" || is_on_player "$next_pos"; then
		respawn_enemy
		return
	fi

	EN_FIFO+=("$next_pos")
	EN_DIR="$chosen"
	EN_POS="$next_pos"
	draw "$EN_POS" "${BLU}${ENM}"
	if [[ ${#EN_FIFO[@]} -gt $EN_TARGET_SIZE ]]; then
		tail_pos="${EN_FIFO[0]}"
		EN_FIFO=("${EN_FIFO[@]:1}")
		draw "$tail_pos" "${NOO}"
	fi
}
# own collision
# @return 0 if dead, 1 if alive
player_dead() {
	#echo "Score: $SCORE -- Death: head ${POS} found in snake ${FIFO[@]}" >log
	[[ " ${FIFO[*]} " =~ " ${POS} " ]] && return 0
	[[ " ${EN_FIFO[*]} " =~ " ${POS} " ]] && return 0
	return 1
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
	# only spawn every 20th frame and if no other exists
	#if (($1 % 20)) || ! [[ $APP == "" ]]; then
	if (($1 % $ARR)) || ! [[ $APP == "" ]]; then
		return
	fi
	# spawn apple
	ACN=0
	APP_SPAWN_X=$((RANDOM % (X_MAX - 1) + 1))
	APP_SPAWN_Y=$((RANDOM % Y_MAX + 2))
	APP=$(((APP_SPAWN_Y - 1) * X_MAX + APP_SPAWN_X))
	if [[ " ${FIFO[*]} " =~ " ${APP} " ]] || [[ " ${EN_FIFO[*]} " =~ " ${APP} " ]]; then
		APP=""
	else
		draw $APP "${GRN}${APL}"
	fi
	#draw $APP "${GRN}${APL}"
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
	SCORE=$(($SCORE + $APL_PLUS))
	#SPF=$(($SPF - 1))
}
# updates player for next frame
update_player() {
	# check for apple
	if [[ "$APP" -eq "$POS" ]]; then
		APP=""
		FIFO+=("$POS")
		increase_score
	fi
	# push new pos
    FIFO+=("$POS")
	draw $POS "${GRN}${PLR}"
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
		spawn_enemy
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
	spawn_enemy
}
# calculates and loads one frame
# @return 0 if dead, 1 if alive after frame
loadframe() {
	printf "\033[1D"
    # print debug info"
    printf "\033[1A\033[K"
    echo "frame=$var, input=$input, DIR=$DIR, SCORE=$SCORE, KILLS=$KILL_COUNT"
	# frame
    printf "\033[s"
    update_pos
    if player_dead && [[ ! $DIR == "" ]]; then
         return 0
	fi
    update_player
	update_enemy
    update_apple "$var"
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
stop_game "Game Over (collision)"

