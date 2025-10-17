package main

import "core:log"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math/linalg"

Window : struct{
	handler: glfw.WindowHandle, 
	w, h: i32
}

ROWS 			 :: 10
COLUMNS 		 :: 10
CELL_SIZE 		 :: 64
MAX_NUM_ENTITIES :: 50


E_TEXTURE :: enum{
	TL, TM, TR,
	ML, MM, MR,
	BL, BM, BR,
	DIRTY_PIG,
	CLEAN_PIG,
	BOX, BUTTON,
	GOAL
}

E_ENTITY :: enum{
	PLAYER,
	GOAL,
	BUTTON,
	BOX
}


textures : map[E_TEXTURE]u32

Actions :: enum{
	WIN,
	PRESSABLE,
	PUSHABLE
}

ActionFlags :: bit_set[Actions]

Entity :: struct{
	class: Class,
	flags: ActionFlags,
	position: Vec2,
	direction: Vec2,
	texture: u32,
	moving: bool,
}

Class :: union{
	Object,
	Player
}

Player :: struct{
}

Object :: struct {
}


Cell :: struct{
	bg_texture: u32,
	entity_id: u32,
	wall: bool
}

Game : struct{
	board: [ROWS][COLUMNS]Cell,
	entity_count: i32,
	entities: [50]Entity,
	keys_down: [glfw.KEY_LAST]bool,
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
	load_texture("assets/2D/clean_pig.png", .CLEAN_PIG)
	load_texture("assets/2D/box.png", .BOX)
	load_texture("assets/2D/button.png", .BUTTON)


	grid_program := load_shaders("grid_vs.glsl", "grid_fs.glsl")

	offset_x, offset_y := get_offset(ROWS, COLUMNS)
	grid_vao := set_grid(ROWS, COLUMNS, offset_x, offset_y)

	entities_zero()
	set_board()
	Game.entity_count = 1

	entity, id := entity_new(.PLAYER, {4, 4})
	entity_set(id, entity)
	
	gl.UseProgram(grid_program)
	gl.Uniform1i(gl.GetUniformLocation(grid_program, "texture1"), 0)
	main_loop: for (!glfw.WindowShouldClose(Window.handler)) {
		current_time := f32(glfw.GetTime())
		delta_time = current_time - last_frame
		last_frame = current_time
		process_input(Window.handler)

		// MovePlayer()
		s_collide()
		entity_set_dir(PLAYER_INDEX, {0, 0})

		// RENDER
		gl.ClearColor(0.2, 0.3, 0.3, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		s_draw(grid_program, grid_vao)

		glfw.SwapBuffers(Window.handler)
		glfw.PollEvents() 
	}
	return
}

EMPTY_INDEX :: 0
PLAYER_INDEX :: 1

entity_set:: proc(id: u32, entity: Entity){
	Game.entities[id] = entity
}

entity_set_dir:: proc(id: u32, dir: Vec2){
	Game.entities[id].direction = dir
}

entity_set_pos:: proc(id: u32, pos: Vec2){
	Game.entities[id].position = pos
}

entity_get :: proc(id: u32)-> Entity{
	return Game.entities[id]
}

entity_get_pos :: proc(id: u32)-> Vec2{
	return Game.entities[id].position 
}

entity_get_texture :: proc(id: u32)-> u32{
	return Game.entities[id].texture 
}

entity_get_dir :: proc(id: u32)-> Vec2{
	return Game.entities[id].direction
}

entity_new :: proc(class: E_ENTITY, position: Vec2)->(Entity, u32){
	entity_prefab := #sparse[E_ENTITY]Entity{
		.PLAYER = Entity{class = Player{}, flags = {}, position = {0, 0}, texture = textures[.DIRTY_PIG]},
		.GOAL = Entity{class = Object{}, flags = {.WIN}, position = {0, 0}, texture = textures[.GOAL]},
		.BUTTON = Entity{class = Object{}, flags = {.PRESSABLE}, position = {0, 0}, texture = textures[.BUTTON]},
		.BOX = Entity{class = Object{}, flags = {.PUSHABLE}, position = {0, 0}, texture = textures[.BOX]},
	}

	new_entity := entity_prefab[class]
	new_entity.position = position

	entity_index := Game.entity_count
	Game.entity_count += 1

	return new_entity, u32(entity_index)
}

// TODO: LOOP OVER
entities_zero :: proc(){
	Game.entity_count = 0
}

s_draw :: proc(shader: u32, vao: VAO){
	gl.UseProgram(shader)
	gl.BindVertexArray(vao)

	ortho := linalg.matrix_ortho3d_f32(0, f32(Window.w), f32(Window.h), 0, 0, 1)
	set_mat4(shader, "ortho", &ortho)

	n:i32=0
	for row, i in Game.board{
		for cell, j in row{
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, cell.bg_texture)
			gl.DrawArrays(gl.TRIANGLES, n * 6, 6)
			// // TODO: Draw seprately.
			// TEXTURE IS EMPTY!
			// if cell.entity_id > 0 && cell.entity_id < MAX_NUM_ENTITIES{
			// 	gl.ActiveTexture(gl.TEXTURE0)
			// 	gl.BindTexture(gl.TEXTURE_2D, Game.entities[cell.entity_id].texture)
			// 	gl.DrawArrays(gl.TRIANGLES, n * 6, 6)
			// }

			n +=1
		}
	}
	for i in 0..<Game.entity_count{
		if i == 0{continue}
		entity := entity_get(u32(i))
		player_cell := cell_get_by_pos(entity.position)
		// log.info(entity, player_cell, entity.texture)
		log.info(i)
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, entity.texture)
		gl.DrawArrays(gl.TRIANGLES, i32(player_cell), 6)
		gl.BindVertexArray(0)
	}
}

cell_get_by_pos :: proc(pos: Vec2)->f32{
	return (pos.y + pos.x * len(Game.board)) * 6
} 



