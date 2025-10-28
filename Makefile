make: 
	odin build ./src/. -out:snake_puzzle

run:
	odin build ./src/. -out:./bin/snake_puzzle -debug
	./bin/snake_puzzle

debug: 
	odin build ./src/. -out:./bin/debug_snake -debug
	gdb ./bin/debug_snake
