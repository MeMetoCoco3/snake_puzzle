package main

import "core:log"
import "core:fmt"
// import "core:os"
import "core:mem"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math/linalg"

CELL_SIZE 		 :: 64
MAX_NUM_ENTITIES :: 50
MAX_NUM_INDEXES  :: 100

E_TEXTURE :: enum
{
	TL, TM, TR,
	ML, MM, MR,
	BL, BM, BR,
	DIRTY_PIG,
	CLEAN_PIG,
	BOX, BUTTON,
	GOAL, CROCO,
}

E_ENTITY :: enum
{
	PLAYER,
	GOAL,
	BUTTON,
	BOX,
	CROCO
}



Actions :: enum
{
	WIN,
	STOMPABLE, 
	PRESSABLE,
	PUSHABLE,
	MOVER,
	GROUNDED,
	ENEMY
}

ActionFlags :: bit_set[Actions]

Entity :: struct
{
	class: Class,
	flags: ActionFlags,
	position: Vec2,
	direction: Vec2,

	texture: u32,
	uv_flip: Vec2,

	moved: bool,

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
	linked_entity: u32
}


Cell :: struct
{
	bg_texture: u32,
	entities_id: [3]u32,
	entity_count: u32,
	wall: bool,
	no_bg: bool,
}

Window : struct
{
	handler: glfw.WindowHandle, 
	w, h: i32
}

Game : struct
{
	scene: Scene,
	input_made: bool,
	keys_down: [glfw.KEY_LAST]bool,
}

MAX_ROWS :: 10
MAX_COLUMNS: : 10
MAX_GEOMETRY_POINTS_PER_BOARD :: 6 * MAX_ROWS * MAX_COLUMNS

Scene :: struct
{
	name: string,
	board: [MAX_ROWS][MAX_COLUMNS]Cell,
	entity_count: i32,
	entities: [50]Entity,
	rows: int,
	columns:int,
	textures: map[E_TEXTURE]u32
}



main :: proc() 
{
	context.logger = log.create_console_logger()

	when ODIN_DEBUG
	{
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer 
		{
			if len(track.allocation_map) > 0 
			{
				for _, entry in track.allocation_map do fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
			}
			mem.tracking_allocator_destroy(&track)
		}
	}


	init_glfw()
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	
	textures := make(map[E_TEXTURE]u32)
	load_texture("assets/2D/bl.png", .BL, &textures)
	load_texture("assets/2D/bm.png", .BM, &textures)
	load_texture("assets/2D/br.png", .BR, &textures)
	load_texture("assets/2D/ml.png", .ML, &textures)
	load_texture("assets/2D/mm.png", .MM, &textures)
	load_texture("assets/2D/mr.png", .MR, &textures)
	load_texture("assets/2D/tl.png", .TL, &textures)
	load_texture("assets/2D/tm.png", .TM, &textures)
	load_texture("assets/2D/tr.png", .TR, &textures)
	load_texture("assets/2D/dirty_pig.png", .DIRTY_PIG, &textures)
	load_texture("assets/2D/clean_pig.png", .CLEAN_PIG, &textures)
	load_texture("assets/2D/box.png", .BOX, &textures)
	load_texture("assets/2D/button.png", .BUTTON, &textures)
	load_texture("assets/2D/flag.png", .GOAL, &textures)
	load_texture("assets/2D/crocodile.png", .CROCO, &textures)

	bg_color := get_pixel_from_image("assets/2D/tl.png", 0, 0)

	grid_program := load_shaders("grid_vs.glsl", "grid_fs.glsl")

	Game.scene.textures = textures
	load_scene("scenes/01.scene", &Game.scene)
	
	offset_x, offset_y := get_offset(i32(Game.scene.columns), i32(Game.scene.rows))
	grid_vao := set_grid(len(Game.scene.board), len(Game.scene.board[0]), offset_x, offset_y)


	gl.UseProgram(grid_program)
	gl.Uniform1i(gl.GetUniformLocation(grid_program, "texture1"), 0)
	
	free_all(context.temp_allocator)



	fmt.println(Game.scene.textures)
	main_loop: 
	for (!glfw.WindowShouldClose(Window.handler)) 
	{
		current_time := f32(glfw.GetTime())
		delta_time = current_time - last_frame
		last_frame = current_time
		s_input(Window.handler, &Game.scene)

		if Game.input_made
		{
			s_collide(&Game.scene)
			s_move(&Game.scene)
			s_static_acctions(&Game.scene)
			Game.input_made = false
			entities_print(0, 6, scene = &Game.scene)
		}
			
		clear_color(bg_color)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		s_draw(grid_program, grid_vao, &Game.scene)

		glfw.SwapBuffers(Window.handler)
		glfw.PollEvents() 

	}

	delete(Game.scene.textures)
	return
}

//////////////
// ENTITIES //
//////////////
EMPTY_INDEX :: 0
PLAYER_INDEX :: 1

entity_new :: proc(class: E_ENTITY, scene: ^Scene)-> (Entity, u32)
{
	textures := scene.textures
	entity_prefab := #sparse[E_ENTITY]Entity \
	{
		.PLAYER = Entity{class = Player{}, flags = {}, position = {-1, -1}, texture = textures[.DIRTY_PIG], active = true, uv_flip = {1, 1}},
		.GOAL = Entity{class = Object{}, flags = {.WIN}, position = {-1, -1}, texture = textures[.GOAL], active = true, uv_flip = {1, 1}},
		.BUTTON = Entity{class = Object{}, flags = {.PRESSABLE, .GROUNDED}, position = {-1, -1}, texture = textures[.BUTTON], active = true, uv_flip = {1, 1}},
		.BOX = Entity{class = Object{}, flags = {.PUSHABLE}, position = {-1, -1}, texture = textures[.BOX], active = true, uv_flip = {1, 1}},
		.CROCO = Entity{class = Object{}, flags = {.MOVER, .ENEMY}, position = {-1, -1}, texture = textures[.CROCO], active = true, uv_flip = {1, 1}},
	}

	new_entity := entity_prefab[class]

	entity_index := scene.entity_count
	scene.entity_count += 1

	return new_entity, u32(entity_index)
}

entity_add:: proc(entity: Entity, id: u32, scene: ^Scene) { scene.entities[id] = entity }


entity_set:: proc(id: u32, entity: Entity, position: Vec2, scene: ^Scene)
{
	scene.entities[id] = entity
	count_entities := entities_count_on_cell(position, scene^)
	scene.board[i32(position.y)][int(position.x)].entities_id[count_entities] = id
	scene.board[i32(position.y)][int(position.x)].entity_count += 1
}

entity_new_set :: proc(class: E_ENTITY, position: Vec2, scene: ^Scene)-> u32
{
	entity, id := entity_new(class, scene)
	entity.position = position
	entity_set(id, entity, position, scene)
	return id
}

entities_count_on_cell :: proc(pos: Vec2, scene: Scene)-> u32    	 { return scene.board[i32(pos.y)][i32(pos.x)].entity_count }
entity_set_dir 		   :: proc(id: u32, dir: Vec2, scene: ^Scene)    { scene.entities[id].direction = dir  }
entity_set_active      :: proc(id: u32, state: bool, scene: ^Scene)  { scene.entities[id].active = state }
entity_set_uv 	:: proc(id: u32, u_flip: Vec2, scene: ^Scene)        { scene.entities[id].uv_flip = u_flip }

entity_set_link :: proc(id_src: u32, id_dst: u32, scene: ^Scene)
{
	
	switch &obj in scene.entities[id_src].class {
		case Object:
			obj.linked_entity = id_dst
		case Player:
			log.infof("Cannot link id: %v into id: %v", id_dst, id_src)
			log.infof("DESTINY ENTITY: %v", entity_get(id_dst, scene))
			log.infof("SOURCE ENTITY: %v", entity_get(id_src, scene))
	}
}


entity_get         :: proc(id: u32, scene: ^Scene)-> Entity	 { return scene.entities[id] 		  }
entity_get_active  :: proc(id: u32, scene: ^Scene)-> bool	 	 { return scene.entities[id].active	  }
entity_get_pos     :: proc(id: u32, scene: ^Scene)-> Vec2		 { return scene.entities[id].position  }
entity_get_texture :: proc(id: u32, scene: ^Scene)-> u32		 { return scene.entities[id].texture   }
entity_get_dir     :: proc(id: u32, scene: ^Scene)-> Vec2		 { return scene.entities[id].direction }

entity_draw :: proc(entity: Entity, program: u32)
{
	vbo_pos := triangle_cell_get_by_pos(entity.position)
	
	set_vec2(program, "u_flip", entity.uv_flip)

	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, entity.texture)
	gl.DrawArrays(gl.TRIANGLES, i32(vbo_pos), 6)
}

entity_move :: proc(id: u32, curr_pos: Vec2, next_pos: Vec2, scene: ^Scene)
{
	curr_cell := cell_get_by_pos(curr_pos, scene)
	next_cell := cell_get_by_pos(next_pos, scene)

	e_prev_count := curr_cell.entity_count

	for i in 0..< e_prev_count 
	{
		if (curr_cell.entities_id[i] == id) 
		{
			scene.board[i32(curr_pos.y)][int(curr_pos.x)].entities_id[i] = EMPTY_INDEX
			scene.board[i32(curr_pos.y)][int(curr_pos.x)].entity_count -= 1
		}
	}	

	e_next_count := next_cell.entity_count
	scene.board[i32(next_pos.y)][int(next_pos.x)].entities_id[e_next_count] = id
	scene.board[i32(next_pos.y)][int(next_pos.x)].entity_count += 1
	scene.entities[id].position = next_pos


	dir := curr_pos - next_pos
	if dir.y == 0 do entity_set_uv(u32(id), {-dir.x, 1}, scene)
}

entities_get_from_pos :: proc(pos: Vec2, scene: ^Scene)->(entities: [2]Entity, ids: [2]u32, count: u32)
{
	cell := cell_get_by_pos(pos, scene)
	count = cell.entity_count
	if cell_is_empty(cell) do return {}, {}, 0
	if cell.entities_id[0] < 1 do return {}, {}, 0

	if count == 1
	{
		ids = {cell.entities_id[0], 0}
		entities[0] = scene.entities[ids[0]]
		entities[1] = {}
	}
	else 
	{
		ids = {cell.entities_id[0], cell.entities_id[1]}
		entities[0] = scene.entities[ids[0]]
		entities[1] = scene.entities[ids[1]]
	}

	return 
}

entities_zero :: proc(scene: ^Scene){
	for i in 0..<len(scene.entities)
	{
		scene.entities[i] = {}
	}
	scene.entity_count = 0
}

entities_print :: proc(from:i32 = 0, to:i32 = MAX_NUM_ENTITIES, p_total:bool = false, scene: ^Scene)
{
	if p_total do fmt.printfln("Total: %v", Game.scene.entity_count)
	for x in from..<to
	{
		fmt.printfln("%v: %v", x, Game.scene.entities[x])
	}
}

board_print_entities :: proc(row_start:= 0, row_to:= -1, column_start:= 0, column_to:= -1, scene: ^Scene){
	ROW_TO := row_to
	COL_TO := column_to
	if ROW_TO == -1 do ROW_TO = len(scene.board)
	if COL_TO == -1 do COL_TO = len(scene.board[0])
	
	for i in row_start..= ROW_TO
	{
		for j in column_start..= COL_TO do fmt.printf("%v ", scene.board[i][j].entities_id[0])
		fmt.println()
	}
}

board_print_bg :: proc(row_start:= 0, row_to:= -1, column_start:= 0, column_to:= -1, scene: ^Scene){
	ROW_TO := row_to
	COL_TO := column_to
	if ROW_TO == -1 do ROW_TO = len(scene.board)
	if COL_TO == -1 do COL_TO = len(scene.board[0])
	
	for i in row_start..< ROW_TO
	{
		for j in column_start..< COL_TO do fmt.printf("%v ", scene.board[i][j].bg_texture)
		fmt.println()
	}
	
}



/////////////
// SYSTEMS //
/////////////
s_draw :: proc(shader: u32, vao: VAO, scene: ^Scene)
{
	gl.UseProgram(shader)
	gl.BindVertexArray(vao)

	ortho := linalg.matrix_ortho3d_f32(0, f32(Window.w), f32(Window.h), 0, 0, 1)
	set_mat4(shader, "ortho", &ortho)

	n:i32 = 0

	set_vec2(shader, "u_flip", {1, 1})
	for i in 0..<scene.rows
	{
		for j in 0..<scene.columns
		{
			cell := scene.board[i][j]
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, cell.bg_texture)
			gl.DrawArrays(gl.TRIANGLES, n * 6, 6)
			n +=1
		}
	}

	for i in PLAYER_INDEX + 1..<scene.entity_count
	{
		if i == 0 || !entity_get_active(u32(i), scene) { continue }

		entity_draw(entity_get(u32(i), scene), shader)
	}

	entity_draw(entity_get(PLAYER_INDEX, scene), shader)
	gl.BindVertexArray(0)
}

s_input :: proc(window: glfw.WindowHandle, scene: ^Scene) 
{
	if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS 
	{
		glfw.SetWindowShouldClose(window, true)
	}

	if glfw.GetKey(window, glfw.KEY_UP) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_UP]
		{
			entity_set_dir(PLAYER_INDEX, {-1, 0}, scene)
			Game.keys_down[glfw.KEY_UP] = true
			Game.input_made = true
		}
	} 
	else { Game.keys_down[glfw.KEY_UP] = false }

	if glfw.GetKey(window, glfw.KEY_DOWN) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_DOWN]
		{
			entity_set_dir(PLAYER_INDEX, {1, 0}, scene)
			Game.keys_down[glfw.KEY_DOWN] = true
			Game.input_made = true
		}
	}
	else { Game.keys_down[glfw.KEY_DOWN] = false }

	if glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_LEFT]
		{
			entity_set_dir(PLAYER_INDEX, {0, -1}, scene)
			Game.keys_down[glfw.KEY_LEFT] = true
			Game.input_made = true
		}
	} 
	else { Game.keys_down[glfw.KEY_LEFT] = false }

	if glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_RIGHT]
		{
			entity_set_dir(PLAYER_INDEX, {0, 1}, scene)
			Game.keys_down[glfw.KEY_RIGHT] = true
			Game.input_made = true
		}
	} 
	else { Game.keys_down[glfw.KEY_RIGHT] = false }
}


triangle_cell_get_by_pos :: proc(pos: Vec2)-> f32
{
	return (pos.y + pos.x * len(Game.scene.board)) * 6
}


cell_is_empty :: proc(cell: Cell)-> bool{ return cell.entity_count == 0 }
cell_empty_or_grounded :: proc(pos: Vec2, scene: ^Scene)-> (e_or_g: bool = true) 
{
	cell := cell_get_by_pos(pos, scene)
	
	for i in 0..<cell.entity_count
	{
		id := cell.entities_id[i]
		entity := entity_get(id, scene)
		if .GROUNDED not_in entity.flags do e_or_g = false
	}
	return 
}

cell_get_by_pos :: proc(pos: Vec2, scene: ^Scene)-> Cell { return scene.board[i32(pos.y)][i32(pos.x)] }

clear_color :: proc(color:Color){gl.ClearColor(f32(color.x)/255, f32(color.y)/255, f32(color.z)/255, f32(color.w)/255)}




