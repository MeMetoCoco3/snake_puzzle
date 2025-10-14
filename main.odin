package main

import "core:log"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math/linalg"

Window : struct{
	handler: glfw.WindowHandle, 
	w, h: i32
}

ROWS :: 10
COLUMNS :: 10
CELL_SIZE :: 64

E_TEXTURE :: enum{
	TL, TM, TR,
	ML, MM, MR,
	BL, BM, BR,
	DIRTY_PIG

}


textures : map[E_TEXTURE]u32

Entity::struct {
	texture: u32
}


Cell :: struct{
	bg_texture: u32,
	entity: Entity
	
}

Game : struct{
	board: [ROWS][COLUMNS]Cell,
	player: struct{
		position: Vec2
	}
}

main :: proc() {
	context.logger = log.create_console_logger()
	init_glfw()
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	load_texture("assets/2D/bl.png", .BL)
	load_texture("assets/2D/bm.png", .BM)
	load_texture("assets/2D/br.png", .BR)
	load_texture("assets/2D/ml.png", .ML)
	load_texture("assets/2D/mm.png", .MM)
	load_texture("assets/2D/mr.png", .MR)
	load_texture("assets/2D/tl.png", .TL)
	load_texture("assets/2D/tm.png", .TM)
	load_texture("assets/2D/tr.png", .TR)
	load_texture("assets/2D/dirty_pig.png", .DIRTY_PIG)

	grid_program := load_shaders("grid_vs.glsl", "grid_fs.glsl")


	offset_x, offset_y := get_offset(ROWS, COLUMNS)
	grid_vao := set_grid(ROWS, COLUMNS, offset_x, offset_y)


	Game.board = [ROWS][COLUMNS]Cell{}
	for i in 0..<ROWS{
		for j in 0..<COLUMNS{
			if j == 1 && (i > 1 && i < 8){
				Game.board[i][j].bg_texture = textures[.TM]
				continue
			}

			if j == 8 && (i > 1 && i < 8){ 
				Game.board[i][j].bg_texture = textures[.BM]
				continue
			}

			if i == 1 && (j > 1 && j < 8){
				Game.board[i][j].bg_texture = textures[.ML]
				continue
			}

			if i == 8 && (j > 1 && j < 8){
				Game.board[i][j].bg_texture = textures[.MR]
				continue
			}

			if i < 8 && i > 1 && j < 8 && j > 1{
				Game.board[i][j].bg_texture = textures[.MM]
				continue
			} else {
				Game.board[i][j].bg_texture = textures[.DIRTY_PIG]
			}
		}
	}


	Game.board[1][1].bg_texture = textures[.TL]
	Game.board[1][8].bg_texture = textures[.BL]
	Game.board[8][1].bg_texture = textures[.TR]
	Game.board[8][8].bg_texture = textures[.BR]





	// gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE) // Wireframe mode

	gl.UseProgram(grid_program)
	gl.Uniform1i(gl.GetUniformLocation(grid_program, "texture1"), 0)
	main_loop: for (!glfw.WindowShouldClose(Window.handler)) {
		process_input(Window.handler)

		// RENDER
		gl.ClearColor(0.2, 0.3, 0.3, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		DrawBoard(grid_program, grid_vao)


		// Call events and swap buffers
		glfw.SwapBuffers(Window.handler)
		glfw.PollEvents() // Calls functions that we can register as callbacks
	}
	return
}



DrawBoard :: proc(shader: u32, vao: VAO){
	gl.UseProgram(shader)

	ortho := linalg.matrix_ortho3d_f32(0, f32(Window.w), f32(Window.h), 0, 0, 1)
	gl.BindVertexArray(vao)

	set_mat4(shader, "ortho", &ortho)


	n :i32=0
	for row, i in Game.board{
		for cell, j in row{
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, cell.bg_texture)
			gl.DrawArrays(gl.TRIANGLES, n * 6, 6)
			n +=1
		}
	}


}
