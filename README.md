
![image](https://user-images.githubusercontent.com/88790311/209857426-c4af40b6-f6e4-4148-89a0-8e019f0ed1e5.png)

## What is **snash**
*Snash* is my recreation of the popular game *snake*, but using only the programming language *bash*, that you can run in your linux command line.
This project helped me get started with a bit more advanced bash, which is probably the reason why this may not be the most beautiful bash code style you've ever seen :) But it works completely fine :D

## Install and Run
1. Make sure to download all the files, including the resource folder. The easiest way is just to clone this repository:
```
git clone https://github.com/forgottosave/snash.git; cd snash
```
2. Make sure the `snash.sh` file is executable
```
chmod +x snash.sh
```
3. Run the game as you would run any bash file
```
./snash.sh
```
## How to Play
You find the general information when adding the flag `-h` when executing the program. Still here are some explanations:

**Goal**
  - Get your highest score possible.
  - Eat apples (green O) to get more points. Letting them rot (not eating them in time) results in minus points.
  - Don't run into yourself or into a wall, it'll kill you ;)
  - Have fun!

**Control**
  - Change direction with w,a,s,d
