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
SPF=130 # milliseconds per frame
Y_MAX=16
X_MAX=32
MODE=5
INIT_SIZE=3 # initial snake size
APL_PLUS=10
APL_MINUS=-10
# game state
DIR="" # player direction
POS=$(($Y_MAX / 2 * $X_MAX + $X_MAX / 2))
APP="" # apple position
ACN=0 # apple existing counter
SCORE=0 # game score
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
F_SCORES="$THIS_DIR/.scores"
# fifo array for positions
declare -a FIFO


##### ARGUMENT PARSING
case $1 in
-h|--help)
	cat $F_HELPTEXT
    exit 0
;;
-s|--scores)
	cat .scores
	exit 0
;;
-f|--fullscreen)
	Y_MAX=$(($(tput lines) - 2)) #16
	X_MAX=$(($(tput cols)  - 1)) #32
	POS=$(($Y_MAX / 2 * $X_MAX + $X_MAX / 2))
;;
-easy)
	MODE='EASY   (0) '
    SPF=200
    INIT_SIZE=2
    APL_MUNUS=0
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
	# change game difficulty
	MODE="$2"
	SPF=200
	INIT_SIZE=2
	APL_MINUS=0
	[[ $2 -le 0 ]] && break;
	SPF=$((2 * "$SPF" / "$MODE" + 50))
	[[ $SPF -le 10 ]] && SPF=10
	[[ $SPF -ge 200 ]] && SPF=200
	INIT_SIZE=$(("$MODE" / 4 + "$INIT_SIZE"))
	APL_MINUS=$(("$APL_MINUS" - "$MODE" * 2))
;;
esac


##### METHODS
# game end
stop_game() { # $1=end_string
	printf "\033[5D\033[s\033[1A\033[K$1  Score: $SCORE\033[u"
	touch $F_SCORES
	echo "$MODE // Death: $1 // Score: $SCORE" >> .scores
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
	# only spawn every 20th frame and if no other exists
	if (($1 % 20)) || ! [[ $APP == "" ]]; then
		return
	fi
	# spawn apple
	ACN=0
	APP=$((($RANDOM % ($X_MAX * $Y_MAX)) + $X_MAX + 1))
	if [[ " ${FIFO[*]} " =~ " ${APP} " ]]; then
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
	SPF=$(($SPF - 1))
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
	# draw gamepanel & start
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
    # print debug info"
    printf "\033[1A\033[K"
    echo "frame=$var, input=$input, DIR=$DIR, SCORE=$SCORE"
	# frame
    printf "\033[s"
    update_pos
    if player_dead && [[ ! $DIR == "" ]]; then
         return 0
	fi
    update_player
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
stop_game "Game Over (don't eat yourself)"



