package main

import "core:log"
import "core:fmt"
import "core:mem"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math/linalg"

CELL_SIZE 	  :: 64
MOVE_DURATION :: 0.1


E_TEXTURE :: enum
{
	TL, TM, TR,
	ML, MM, MR,
	BL, BM, BR,
	IBL, IBR, ITL, ITR,
	DIRTY_PIG,
	CLEAN_PIG,
	BOX, BUTTON,
	GOAL, CROCO,
	TRAPDOOR_OPEN, TRAPDOOR_CLOSED,

}

Cell :: struct
{
	bg_texture: u32,
	entities_id: [MAX_ENTITIES_PER_CELL]u32,
	entity_count: u32,
	wall: bool,
	no_bg: bool,
}

Window : struct
{
	handler: glfw.WindowHandle, 
	w, h: i32,
	grid_VAO: VAO,
	grid_shader: u32,
	entity_VAO: VAO,
	entity_shader: u32
}

Game : struct
{
	current_level: i32,
	scene: Scene,
	input_made: bool,
	turn: E_TURN,
	keys_down: [glfw.KEY_LAST]bool,
	load_next: bool,

	moving_sprites: E_TURN,
	movement_timer: f32
}

MAX_ROWS :: 20
MAX_COLUMNS :: 20
MAX_GEOMETRY_POINTS_PER_BOARD :: 6 * MAX_ROWS * MAX_COLUMNS

Scene :: struct
{
	name: string,
	board: [MAX_ROWS][MAX_COLUMNS]Cell,
	entity_count: i32,
	entities: [50]Entity,
	rows: int,
	columns:int,
	textures: map[E_TEXTURE]u32,

	offset: Vec2,
}


E_TURN :: enum
{
	NONE,
	PLAYER,
	OTHERS,
	MOD,
}

main :: proc() 
{
	log.info("Start main")
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
	load_texture("assets/2D/IBL.png", .IBL, &textures)
	load_texture("assets/2D/IBR.png", .IBR, &textures)
	load_texture("assets/2D/ITL.png", .ITL, &textures)
	load_texture("assets/2D/ITR.png", .ITR, &textures)
	load_texture("assets/2D/TRAPDOOR_OPEN.png", .TRAPDOOR_OPEN, &textures)
	load_texture("assets/2D/TRAPDOOR_CLOSED.png", .TRAPDOOR_CLOSED, &textures)

	bg_color := get_pixel_from_image("assets/2D/tl.png", 0, 0)

	Window.grid_shader = load_shaders("shaders/grid_vs.glsl", "shaders/grid_fs.glsl")
	Window.entity_shader = load_shaders("shaders/entity_vs.glsl", "shaders/entity_fs.glsl")
	Game.scene.textures = textures
	load_scene(3)
	
	main_loop: 
	for (!glfw.WindowShouldClose(Window.handler)) 
	{
		current_time := f32(glfw.GetTime())
		delta_time = current_time - last_frame
		last_frame = current_time

		if Game.moving_sprites == .NONE do s_input(Window.handler, &Game.scene)

		if Game.input_made
		{
			#partial switch Game.turn 
			{
				case .PLAYER:
					s_collide_player(PLAYER_INDEX, &Game.scene)

					Game.moving_sprites = .PLAYER
				case .OTHERS:
					for i in PLAYER_INDEX+1..<Game.scene.entity_count do s_collide_enemy(u32(i), &Game.scene)

					s_static_actions(&Game.scene)
					Game.moving_sprites = .OTHERS
				case .NONE:
				case :
					out("WRONG STATE")
			}
			
			Game.turn = .NONE

			if Game.load_next
			{
				entities_zero(&Game.scene)
				load_scene(Game.current_level)
				Game.load_next = false
			}
		} 
		
		if Game.moving_sprites != .NONE
		{
			if Game.movement_timer < 1.0 
			{
				Game.movement_timer += delta_time / MOVE_DURATION
				alpha := min(Game.movement_timer, 1.0)
				for i in PLAYER_INDEX..<Game.scene.entity_count
				{
					if !Game.scene.entities[i].moved do continue
					if !(Game.scene.entities[i].move_turn == Game.moving_sprites) do continue
					e := &Game.scene.entities[i].sprite
					new_position := linalg.lerp(e.start, e.target, alpha)
					e.position = new_position
				}

				if alpha == 1.0 
				{
					Game.moving_sprites += E_TURN(1)
					if Game.moving_sprites == .MOD do Game.moving_sprites = .NONE
					Game.turn = Game.moving_sprites

					Game.movement_timer = 0
					for i in PLAYER_INDEX..<Game.scene.entity_count
					{
						if !(Game.scene.entities[i].move_turn == Game.moving_sprites) do Game.scene.entities[i].moved = false
					}
				}
			}
		}
			
		clear_color(bg_color)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		
		s_draw(&Game.scene)

		glfw.SwapBuffers(Window.handler)
		glfw.PollEvents() 
	}

	end_glfw()
	delete(Game.scene.textures)
	return
}

triangle_cell_get_by_pos :: proc(pos: Vec2, columns: f32)-> f32 { return pos.y * 6 + (pos.x * columns * 6) }
cell_is_empty :: proc(cell: Cell)-> bool{ return cell.entity_count == 0 }
cell_empty_or_grounded :: proc(pos: Vec2, scene: ^Scene)-> (e_or_g: bool = true) 
{
	cell := cell_get_by_pos(pos, scene)
	if cell_is_empty(cell) do return 

	for i in 0..<cell.entity_count
	{
		id := cell.entities_id[i]
		entity := entity_get(id, scene)
		if .GROUNDED not_in entity.flags do e_or_g = false
	}
	return 
}

cell_get_by_pos :: proc(pos: Vec2, scene: ^Scene)-> Cell { return scene.board[i32(pos.x)][i32(pos.y)] }

clear_color :: proc(color:Color){gl.ClearColor(f32(color.x)/255, f32(color.y)/255, f32(color.z)/255, f32(color.w)/255)}




