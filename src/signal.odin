package main

import "core:sys/linux"
import "core:sys/posix"
import "vendor:glfw"
import "core:os"

signal_handler :: proc "c" (signal: posix.Signal)
{
	glfw.SetWindowShouldClose(Window.handler, true)
}



set_posix_signal_handlers:: proc()
{
	posix.signal(posix.Signal.SIGTERM, signal_handler)
	posix.signal(posix.Signal.SIGINT, signal_handler)
	posix.signal(posix.Signal.SIGTSTP, signal_handler)
}
