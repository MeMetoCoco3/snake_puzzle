package main

import "core:log"
import "core:fmt"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math/linalg"

ROWS 			 :: 10
COLUMNS 		 :: 10
CELL_SIZE 		 :: 64
MAX_NUM_ENTITIES :: 50
MAX_NUM_INDEXES  :: 100
MAX_NUM_CELLS_PER_GRID :: 6 * 20 * 20

E_TEXTURE :: enum
{
	TL, TM, TR,
	ML, MM, MR,
	BL, BM, BR,
	DIRTY_PIG,
	CLEAN_PIG,
	BOX, BUTTON,
	GOAL
}

E_ENTITY :: enum
{
	PLAYER,
	GOAL,
	BUTTON,
	BOX
}


textures : map[E_TEXTURE]u32

Actions :: enum
{
	WIN,
	STOMPABLE, 
	PRESSABLE,
	PUSHABLE,
	MOVER,
	GROUNDED,
}

ActionFlags :: bit_set[Actions]

Entity :: struct
{
	class: Class,
	flags: ActionFlags,
	position: Vec2,
	direction: Vec2,
	texture: u32,
	moving: bool,
	active: bool,
}

Class :: union
{
	Object,
	Player
}

Player :: struct{}
Object :: struct{
	data_pressable: u32
}


Cell :: struct
{
	bg_texture: u32,
	entities_id: [2]u32,
	entity_count: u32,
	wall: bool
}

Window : struct
{
	handler: glfw.WindowHandle, 
	w, h: i32
}

Game : struct
{
	input_made: bool,
	board: [ROWS][COLUMNS]Cell,
	entity_count: i32,
	entities: [50]Entity,
	keys_down: [glfw.KEY_LAST]bool,
}

main :: proc() 
{
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
	load_texture("assets/2D/flag.png", .GOAL)

	grid_program := load_shaders("grid_vs.glsl", "grid_fs.glsl")

	offset_x, offset_y := get_offset(ROWS, COLUMNS)
	grid_vao := set_grid(ROWS, COLUMNS, offset_x, offset_y)

	entities_zero()
	board_set()
	Game.entity_count = 1

	entity_new_set(.PLAYER, {4, 4})
	entity_new_set(.BOX, {4, 7})
	// entity_new_set(.BUTTON, {7, 7})
	// goal_id := entity_new_set(.GOAL, {8,8})
	// entity_set_active(goal_id, false)
	// entities_print(to = Game.entity_count, p_total = true)

	gl.UseProgram(grid_program)
	gl.Uniform1i(gl.GetUniformLocation(grid_program, "texture1"), 0)


	entities_print(to = 3, p_total = true)


	board_print(0, ROWS-1, 0, COLUMNS-1)
	main_loop: 
	for (!glfw.WindowShouldClose(Window.handler)) 
	{
		current_time := f32(glfw.GetTime())
		delta_time = current_time - last_frame
		last_frame = current_time
		s_input(Window.handler)

		if Game.input_made
		{
			s_collide()
			s_move()
			
			Game.input_made = false
			entities_print(to = 3, p_total = true)
			board_print(0, ROWS-1, 0, COLUMNS-1)
		}

		gl.ClearColor(0.2, 0.3, 0.3, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		s_draw(grid_program, grid_vao)

		glfw.SwapBuffers(Window.handler)
		glfw.PollEvents() 

	}
	return
}

//////////////
// ENTITIES //
//////////////
EMPTY_INDEX :: 0
PLAYER_INDEX :: 1

entity_new :: proc(class: E_ENTITY, position: Vec2)-> (Entity, u32)
{
	entity_prefab := #sparse[E_ENTITY]Entity \
	{
		.PLAYER = Entity{class = Player{}, flags = {}, position = {-1, -1}, texture = textures[.DIRTY_PIG], active = true},
		.GOAL = Entity{class = Object{}, flags = {.WIN}, position = {-1, -1}, texture = textures[.GOAL], active = true},
		.BUTTON = Entity{class = Object{}, flags = {.PRESSABLE, .GROUNDED}, position = {-1, -1}, texture = textures[.BUTTON], active = true},
		.BOX = Entity{class = Object{}, flags = {.PUSHABLE}, position = {-1, -1}, texture = textures[.BOX], active = true},
	}

	new_entity := entity_prefab[class]
	new_entity.position = position

	entity_index := Game.entity_count
	Game.entity_count += 1

	return new_entity, u32(entity_index)
}

entity_set:: proc(id: u32, entity: Entity)
{
	Game.entities[id] = entity
	count_entities := entities_count_on_cell(entity.position)
	Game.board[i32(entity.position.y)][int(entity.position.x)].entities_id[count_entities] = id
	Game.board[i32(entity.position.y)][int(entity.position.x)].entity_count += 1
}

entity_new_set :: proc(class: E_ENTITY, position: Vec2)-> u32
{
	entity, id := entity_new(class, position)
	entity_set(id, entity)
	return id
}

entities_count_on_cell :: proc(pos: Vec2)-> u32    	  { return Game.board[i32(pos.y)][i32(pos.x)].entity_count }
entity_set_dir 		   :: proc(id: u32, dir: Vec2)    { Game.entities[id].direction = dir  }
entity_set_active      :: proc(id: u32, state: bool)  { Game.entities[id].active = state }

entity_get         :: proc(id: u32)-> Entity	 { return Game.entities[id] 		  }
entity_get_active  :: proc(id: u32)-> bool	 	 { return Game.entities[id].active	  }
entity_get_pos     :: proc(id: u32)-> Vec2		 { return Game.entities[id].position  }
entity_get_texture :: proc(id: u32)-> u32		 { return Game.entities[id].texture   }
entity_get_dir     :: proc(id: u32)-> Vec2		 { return Game.entities[id].direction }

entity_draw :: proc(id: u32)
{
	entity := entity_get(u32(id))
	vbo_pos := triangle_cell_get_by_pos(entity.position)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, entity.texture)
	gl.DrawArrays(gl.TRIANGLES, i32(vbo_pos), 6)
}

entity_move :: proc(id: u32, curr_pos: Vec2, next_pos: Vec2)
{
	curr_cell := cell_get_by_pos(curr_pos)
	next_cell := cell_get_by_pos(next_pos)

	e_prev_count := curr_cell.entity_count

	for i in 0..< e_prev_count 
	{
		if (curr_cell.entities_id[i] == id) 
		{
			Game.board[i32(curr_pos.y)][int(curr_pos.x)].entities_id[i] = EMPTY_INDEX
			Game.board[i32(curr_pos.y)][int(curr_pos.x)].entity_count -= 1
		}
	}	

	e_next_count := next_cell.entity_count
	Game.board[i32(next_pos.y)][int(next_pos.x)].entities_id[e_next_count] = id
	Game.board[i32(next_pos.y)][int(next_pos.x)].entity_count += 1
	Game.entities[id].position = next_pos
}

entities_get_from_pos :: proc(pos: Vec2)->(entities: [2]Entity, ids: [2]u32, count: u32)
{
	cell := cell_get_by_pos(pos)
	count = cell.entity_count
	if cell_is_empty(cell) do return {}, {}, 0
	if cell.entities_id[0] < 1 do return {}, {}, 0

	if count == 1
	{
		ids = {cell.entities_id[0], 0}
		entities[0] = Game.entities[ids[0]]
		entities[1] = {}
	}
	else 
	{
		ids = {cell.entities_id[0], cell.entities_id[1]}
		entities[0] = Game.entities[ids[0]]
		entities[1] = Game.entities[ids[1]]
	}

	return 
}

entities_zero :: proc(){
	for i in 0..<len(Game.entities)
	{
		Game.entities[i] = {}
	}
	Game.entity_count = 0
}

entities_print::proc(from:i32 = 0, to:i32 = MAX_NUM_ENTITIES, p_total:bool = false)
{
	if p_total do fmt.printfln("Total: %v", Game.entity_count)
	for x in from..<to
	{
		fmt.printfln("%v: %v", x, Game.entities[x])
	}
}

board_print:: proc(row_start:= 0, row_to:= -1, column_start:= 0, column_to:= -1){
	ROW_TO := row_to
	COL_TO := column_to
	if ROW_TO == -1 do ROW_TO = len(Game.board)
	if COL_TO == -1 do COL_TO = len(Game.board[0])
	
	for i in row_start..= ROW_TO
	{
		for j in column_start..= COL_TO do fmt.printf("%v ", Game.board[i][j].entities_id[0])
		fmt.println()
	}
	
}


/////////////
// SYSTEMS //
/////////////
s_draw :: proc(shader: u32, vao: VAO)
{
	gl.UseProgram(shader)
	gl.BindVertexArray(vao)

	ortho := linalg.matrix_ortho3d_f32(0, f32(Window.w), f32(Window.h), 0, 0, 1)
	set_mat4(shader, "ortho", &ortho)

	n:i32=0
	for row, i in Game.board
	{
		for cell, j in row
		{
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, cell.bg_texture)
			gl.DrawArrays(gl.TRIANGLES, n * 6, 6)
			n +=1
		}
	}

	for i in PLAYER_INDEX + 1..<Game.entity_count
	{
		if i == 0 || !entity_get_active(u32(i)) { continue }
		entity_draw(u32(i))
	}

	entity_draw(PLAYER_INDEX)
	gl.BindVertexArray(0)
}

s_input :: proc(window: glfw.WindowHandle) 
{
	if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS 
	{
		glfw.SetWindowShouldClose(window, true)
	}

	if glfw.GetKey(window, glfw.KEY_UP) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_UP]
		{
			entity_set_dir(PLAYER_INDEX, {0, -1})
			Game.keys_down[glfw.KEY_UP] = true
			Game.input_made = true
		}
	} 
	else { Game.keys_down[glfw.KEY_UP] = false }

	if glfw.GetKey(window, glfw.KEY_DOWN) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_DOWN]
		{
			entity_set_dir(PLAYER_INDEX, {0, 1})
			Game.keys_down[glfw.KEY_DOWN] = true
			Game.input_made = true
		}
	}
	else { Game.keys_down[glfw.KEY_DOWN] = false }

	if glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_LEFT]
		{
			entity_set_dir(PLAYER_INDEX, {-1, 0})
			Game.keys_down[glfw.KEY_LEFT] = true
			Game.input_made = true
		}
	} 
	else { Game.keys_down[glfw.KEY_LEFT] = false }

	if glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_RIGHT]
		{
			entity_set_dir(PLAYER_INDEX, {1, 0})
			Game.keys_down[glfw.KEY_RIGHT] = true
			Game.input_made = true
		}
	} 
	else { Game.keys_down[glfw.KEY_RIGHT] = false }
}


triangle_cell_get_by_pos :: proc(pos: Vec2)-> f32
{
	return (pos.y + pos.x * len(Game.board)) * 6
}


cell_is_empty :: proc(cell: Cell)-> bool{ return cell.entity_count == 0 }
cell_empty_or_grounded :: proc(pos: Vec2)-> (e_or_g: bool = true) 
{
	cell := cell_get_by_pos(pos)
	
	for i in 0..<cell.entity_count
	{
		id := cell.entities_id[i]
		entity := entity_get(id)
		if .GROUNDED not_in entity.flags do e_or_g = false
	}
	return 
}

cell_get_by_pos :: proc(pos: Vec2)-> Cell { return Game.board[i32(pos.y)][i32(pos.x)] }


