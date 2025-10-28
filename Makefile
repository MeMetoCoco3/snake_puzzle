make: 
	odin build . -out:snake_puzzle

run:
	odin run .

debug: 
	odin build . -out:debug_snake -debug
	gdb debug_snake
