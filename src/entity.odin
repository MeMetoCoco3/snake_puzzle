package main

import "core:log"
import gl"vendor:OpenGL"
import "core:math/linalg"
import "core:fmt"

MAX_NUM_ENTITIES 	  :: 50
MAX_NUM_INDEXES  	  :: 100
MAX_ENTITIES_PER_CELL :: 3

E_ENTITY :: enum
{
	PLAYER,
	GOAL,
	BUTTON,
	BOX,
	CROCO,
	TRAPDOOR,
}



Actions :: enum
{
	WIN,
	STOMPABLE, 
	PRESSABLE,
	PUSHABLE,
	MOVER,
	GROUNDED,
	FALLTHROUGH,
	ENEMY
}

ActionFlags :: bit_set[Actions]

Entity :: struct
{
	class: Class,
	flags: ActionFlags,
	position: Vec2,
	direction: Vec2,

	sprite: Sprite, 

	moved: bool,

	move_turn: E_TURN,
	active: bool,
}

Class :: union
{
	Object,
	Player,
	// Trapdoor,
}


// // Trapdoor :: struct
// {
// 	open: bool
// }

Player :: struct{}
Object :: struct{
	open: bool,
	link_type: E_LINK,
	linked_entity: u32
}

E_LINK :: enum
{
	SET_ACTIVE,
	SET_FALLTHROUGH,
}

Sprite :: struct 
{
	texture: u32,
	uv_flip: Vec2,
	position: Vec2,
	start: Vec2,
	target: Vec2,
	size: Vec2,
	moving: bool,
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
EMPTY_INDEX :: 0
PLAYER_INDEX :: 1

entity_new :: proc(class: E_ENTITY, scene: ^Scene)-> (Entity, u32)
{
	textures := scene.textures
	entity_prefab := #sparse[E_ENTITY]Entity \
	{
		.PLAYER = Entity \ 
		{
			class = Player{}, 
			flags = {}, 
			position = {-1, -1}, 
			sprite = Sprite \
			{
				texture = textures[.DIRTY_PIG], 
				uv_flip = {1, 1},
				moving = false,
			},
			active = true,
		},

		.GOAL = Entity \
		{
			class = Object{
				link_type = .SET_ACTIVE,
			}, 
			flags = {.WIN}, 
			position = {-1, -1}, 
			sprite = Sprite \
			{
				texture = textures[.GOAL], 
				uv_flip = {1, 1},
				moving = false,
			},
			active = true, 
		},

		.BUTTON = Entity \
		{
			class = Object{}, 
			flags = {.PRESSABLE, .GROUNDED}, 
			position = {-1, -1}, 
			sprite = Sprite \
			{
				texture = textures[.BUTTON], 
				uv_flip = {1, 1},
				moving = false,
			},
			active = true, 
		},

		.BOX = Entity \ 
		{
			class = Object{},
			flags = {.PUSHABLE},
			position = {-1, -1},
			sprite = Sprite \ 
			{
				texture = textures[.BOX], 
				uv_flip = {1, 1},
				moving = false
			},
			active = true,
		},

		.CROCO = Entity \
		{
			class = Object{}, 
			flags = {.MOVER, .ENEMY},
			position = {-1, -1},
			sprite = Sprite \
			{
				texture = textures[.CROCO], 
				uv_flip = {1, 1},
				moving = false,
			},
			active = true,
		},

		.TRAPDOOR = Entity \
		{
			class = Object{
				link_type = .SET_FALLTHROUGH,
			}, 
			flags = {.GROUNDED, .FALLTHROUGH},
			position = {-1, -1},
			sprite = Sprite \
			{
				texture = textures[.TRAPDOOR_OPEN], 
				uv_flip = {1, 1},
				moving = false,
			},
			active = true,
		},

	}

	new_entity := entity_prefab[class]

	entity_index := scene.entity_count
	scene.entity_count += 1

	return new_entity, u32(entity_index)
}

entity_add:: proc(entity: Entity, id: u32, scene: ^Scene) { scene.entities[id] = entity }


entity_set :: proc(id: u32, entity: Entity, position: Vec2, scene: ^Scene)
{
	scene.entities[id] = entity
	count_entities := entities_count_on_cell(position, scene^)
	scene.board[i32(position.x)][int(position.y)].entities_id[count_entities] = id
	scene.board[i32(position.x)][int(position.y)].entity_count += 1
}

entity_new_set :: proc(class: E_ENTITY, position: Vec2, scene: ^Scene)-> u32
{
	entity, id := entity_new(class, scene)
	entity.position = position
	entity_set(id, entity, position, scene)
	return id
}

entity_update :: proc(id: u32, entity: Entity, scene: ^Scene) { 
	scene.entities[id] = entity 
}
entities_count_on_cell :: proc(pos: Vec2, scene: Scene)-> u32    	 { return scene.board[i32(pos.x)][i32(pos.y)].entity_count }
entity_set_dir 		   :: proc(id: u32, dir: Vec2, scene: ^Scene)    { scene.entities[id].direction = dir  }
entity_set_active      :: proc(id: u32, state: bool, scene: ^Scene)  { scene.entities[id].active = state }

entity_set_fallthrough   :: proc(id: u32, state: bool, scene: ^Scene)
{ 
	e := &scene.entities[id]
	if state
	{
		e.flags -= {.FALLTHROUGH}
		e.sprite.texture = scene.textures[.TRAPDOOR_CLOSED]
	}
	else 
	{
		e.flags += {.FALLTHROUGH}
		e.sprite.texture = scene.textures[.TRAPDOOR_OPEN]
	}

	cell := cell_get_by_pos(e.position, scene)
	
	if cell.entity_count > 1
	{
		for i in 0..<cell.entity_count
		{
			id := cell.entities_id[i]
			if is_player(id) do out("GOOD")
			else if is_enemy(entity_get(id, scene)^) do entity_kill(id, scene)
		}
	}
}

entity_kill :: proc(id: u32, scene: ^Scene)
{
	entity_set_active(id, false, scene)

	entity := entity_get(id, scene)
	curr_pos := entity.position
	curr_cell := cell_get_by_pos(curr_pos, scene)

	e_prev_count := curr_cell.entity_count
	
	position_on_entities_id : u32
	for i in 0..< e_prev_count 
	{
		if (curr_cell.entities_id[i] == id) 
		{
			scene.board[i32(entity.position.x)][int(entity.position.y)].entities_id[i] = EMPTY_INDEX
			scene.board[i32(entity.position.x)][int(entity.position.y)].entity_count -= 1
			position_on_entities_id = i
		} 
	}	
	if position_on_entities_id != MAX_ENTITIES_PER_CELL-1 && e_prev_count > 1
	{
		entities_id := &scene.board[i32(entity.position.x)][int(entity.position.y)].entities_id 
		for i in position_on_entities_id+1..< MAX_ENTITIES_PER_CELL
		{
			entities_id[i-1] = entities_id[i]
			entities_id[i] = EMPTY_INDEX
		}
	}
}

entity_set_uv 	:: proc(id: u32, u_flip: Vec2, scene: ^Scene)        { scene.entities[id].sprite.uv_flip = u_flip }

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


entity_get         :: proc(id: u32, scene: ^Scene)-> ^Entity	 { return &scene.entities[id] 		  }
entity_get_active  :: proc(id: u32, scene: ^Scene)-> bool	 	 { return scene.entities[id].active	  }
entity_get_pos     :: proc(id: u32, scene: ^Scene)-> Vec2		 { return scene.entities[id].position  }
entity_get_texture :: proc(id: u32, scene: ^Scene)-> u32		 { return scene.entities[id].sprite.texture   }
entity_get_dir     :: proc(id: u32, scene: ^Scene)-> Vec2		 { return scene.entities[id].direction }
entity_get_moved :: proc(id: u32, scene: ^Scene)-> bool {return scene.entities[id].moved }
entity_set_moved :: proc(id: u32, state: bool, scene: ^Scene){scene.entities[id].moved = state}

entity_draw :: proc(sprite: Sprite, program: u32, scene: ^Scene)
{
	model := linalg.matrix4_translate_f32(Vec3{sprite.position.x, sprite.position.y, 0})
	// TODO: NOT HARDCODE THE SIZE OBVIOUSLY
    model = model * linalg.matrix4_scale_f32(Vec3{64, 64, 1})
	set_vec2(program, "u_flip", sprite.uv_flip)
	set_mat4(program, "model", &model)

	gl.BindTexture(gl.TEXTURE_2D, sprite.texture)

	gl.BindVertexArray(Window.entity_VAO)
	gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
}

entity_move :: proc(id: u32, entity: ^Entity, next_pos: Vec2, scene: ^Scene)
{
	curr_pos := entity.position
	curr_cell := cell_get_by_pos(curr_pos, scene)
	next_cell := cell_get_by_pos(next_pos, scene)

	e_prev_count := curr_cell.entity_count
	
	position_on_entities_id : u32
	for i in 0..< e_prev_count 
	{
		if (curr_cell.entities_id[i] == id) 
		{
			scene.board[i32(entity.position.x)][int(entity.position.y)].entities_id[i] = EMPTY_INDEX
			scene.board[i32(entity.position.x)][int(entity.position.y)].entity_count -= 1
			position_on_entities_id = i
		} 
	}	
	if position_on_entities_id != MAX_ENTITIES_PER_CELL-1 && e_prev_count > 1
	{
		entities_id := &scene.board[i32(entity.position.x)][int(entity.position.y)].entities_id 
		for i in position_on_entities_id+1..< MAX_ENTITIES_PER_CELL
		{
			entities_id[i-1] = entities_id[i]
			entities_id[i] = EMPTY_INDEX
		}
	}
	

	e_next_count := next_cell.entity_count
	scene.board[i32(next_pos.x)][int(next_pos.y)].entities_id[e_next_count] = id
	scene.board[i32(next_pos.x)][int(next_pos.y)].entity_count += 1
	entity.position = next_pos
	
	entity.sprite.start = screen_position_from_grid_position(curr_pos, scene^)
	entity.sprite.target = screen_position_from_grid_position(next_pos, scene^)

	entity.move_turn = .PLAYER if id == PLAYER_INDEX else .OTHERS
	entity.moved = true
	dir := curr_pos - next_pos
	if dir.x == 0 do entity.sprite.uv_flip = Vec2{-dir.y, 1}
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

    for i in 0..<scene.rows 
	{
        for j in 0..<scene.columns 
		{
            cell := &scene.board[i][j]
			cell.wall = false
			cell.bg_texture = 0
            cell.entity_count = 0
            for k in 0..<MAX_ENTITIES_PER_CELL do cell.entities_id[k] = 0
        }
    }

	for i in 0..<len(scene.entities) do scene.entities[i] = {}
	scene.entity_count = 0
}

entities_print :: proc(from:i32 = 0, to:i32 = MAX_NUM_ENTITIES, p_total:bool = false, scene: ^Scene)
{
	if p_total do fmt.printfln("Total: %v", Game.scene.entity_count)
	for x in from..<to
	{
		fmt.printfln("%v: %v", x, Game.scene.entities[x])
	}
	fmt.println()
}

board_print_entities :: proc(row_start:= 0, row_to:= -1, column_start:= 0, column_to:= -1, scene: ^Scene){
	ROW_TO := row_to
	COL_TO := column_to
	if ROW_TO == -1 do ROW_TO = scene.rows 
	if COL_TO == -1 do COL_TO = scene.columns
	
	for j in row_start..< ROW_TO
	{
		for i in column_start..< COL_TO do fmt.printf("%v ", scene.board[j][i].entities_id[0])
		fmt.println()
	}
	fmt.println()
}

board_print_bg :: proc(row_start:= 0, row_to:= -1, column_start:= 0, column_to:= -1, scene: ^Scene){
	ROW_TO := row_to
	COL_TO := column_to
	if ROW_TO == -1 do ROW_TO = scene.rows
	if COL_TO == -1 do COL_TO = scene.columns
	
	for j in row_start..< ROW_TO
	{
		for i in column_start..< COL_TO do fmt.printf("%v ", scene.board[i][j].bg_texture)
		fmt.println()
	}
	
}



