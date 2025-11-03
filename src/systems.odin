package main

import gl"vendor:OpenGL"
import "core:fmt"
import "core:math/linalg"
import "vendor:glfw"

///////////////////////////////////////////////////////////////////////////
s_draw :: proc(scene: ^Scene)
{
	gl.UseProgram(Window.grid_shader)
	gl.BindVertexArray(Window.grid_VAO)

	ortho := linalg.matrix_ortho3d_f32(0, f32(Window.w), f32(Window.h), 0, -1, 1)
	set_mat4(Window.grid_shader, "ortho", &ortho)

	n:i32 = 0

	set_vec2(Window.grid_shader, "u_flip", {1, 1})
	gl.ActiveTexture(gl.TEXTURE0)
	for i in 0..<scene.rows
	{
		for j in 0..<scene.columns
		{
			cell := scene.board[i][j]
			if cell.bg_texture == 0 
			{
				n+=1
				continue
			}
			gl.BindTexture(gl.TEXTURE_2D, cell.bg_texture)
			gl.DrawArrays(gl.TRIANGLES, n * 6, 6)
			n +=1
		}
	}


	gl.BindVertexArray(Window.entity_VAO)
	gl.UseProgram(Window.entity_shader)
	gl.ActiveTexture(gl.TEXTURE0)

	set_mat4(Window.entity_shader, "ortho", &ortho)
	for i in PLAYER_INDEX + 1..<scene.entity_count
	{
		if i == 0 || !entity_get_active(u32(i), scene) { continue }
		entity_draw(entity_get(u32(i), scene).sprite, Window.entity_shader, scene)
	}

	entity_draw(entity_get(PLAYER_INDEX, scene).sprite, Window.entity_shader, scene)

	gl.BindVertexArray(0)
}


///////////////////////////////////////////////////////////////////////////
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
			Game.turn += E_TURN(1)
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
			Game.turn += E_TURN(1)
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

			Game.turn += E_TURN(1)
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

			Game.turn += E_TURN(1)
		}
	} 
	else { Game.keys_down[glfw.KEY_RIGHT] = false }
}


///////////////////////////////////////////////////////////////////////////
s_collide :: proc(scene: ^Scene)
{
	for i in 0..<scene.entity_count
	{
		entity := entity_get(u32(i), scene)
		if !entity.active do continue
		if is_player(u32(i)) do s_collide_player(u32(i), scene) 
		else if is_enemy(entity^) do s_collide_enemy(u32(i), scene)
	}
}

@(private)
s_collide_player :: proc(i: u32, scene: ^Scene)
{
	entity := entity_get(u32(i), scene)
	
	new_position := entity.position + entity.direction
	if is_wall(new_position, scene^) || entity.direction == {0, 0} do return

	entities, entities_ids, e_count := entities_get_from_pos(new_position, scene)	

	for j := i32(e_count)-1; j >= 0; j -=1
	{
		if entities_ids[j] > 0 && entity_get_active(entities_ids[j], scene)
		{
			if .WIN in entities[j].flags 
			{
				Game.load_next = true
				Game.current_level += 1
			}

			if .ENEMY in entities[j].flags {
				fmt.println("KIIASIDAK")
 glfw.SetWindowShouldClose(Window.handler, true)
			}
						
			if .PUSHABLE in entities[j].flags
			{
				pushed_new_position := entity.position + (2*entity.direction)
				ok_to_push := cell_empty_or_grounded(pushed_new_position, scene)
				if !is_wall(new_position+entity.direction, scene^) && ok_to_push
				{
					push_entity := entity_get(entities_ids[j], scene)
					entity_move(entities_ids[j], push_entity,pushed_new_position, scene)
					entity_move(u32(i), entity, new_position, scene)
					push_entity.move_turn = .PLAYER
				} 
				else 
				{
					return
				}
				continue
			}
		}
	}

	if !entity.moved do entity_move(u32(i), entity, new_position, scene)
}

@(private)
s_collide_enemy :: proc(i: u32, scene: ^Scene)
{
	entity := entity_get(u32(i), scene)

	if entity.direction == {0, 0} || !entity.active do return

	new_position := entity.position + entity.direction
	
	if is_wall(new_position, scene^) 
	{
		entity.direction = Vec2{-entity.direction.x, -entity.direction.y}
		new_position = entity.position + entity.direction

		if is_wall(new_position, scene^) do return
	} 
	

	entities, entities_ids, e_count := entities_get_from_pos(new_position, scene)	
	for j := i32(e_count)-1; j >= 0; j -=1
	{
		if entities_ids[j] > 0 && entity_get_active(entities_ids[j], scene)
		{
			if is_player(entities_ids[j]) 
			{
				glfw.SetWindowShouldClose(Window.handler, true) 
			}

			if .PUSHABLE in entities[j].flags
			{
				pushed_new_position := entity.position + (2 * entity.direction)
				ok_to_push := cell_empty_or_grounded(pushed_new_position, scene)
				if !is_wall(pushed_new_position, scene^) && ok_to_push
				{
					fmt.println("JAMON")
					pushed_entity := entity_get(entities_ids[j], scene)
					entity_move(entities_ids[j],pushed_entity, pushed_new_position, scene)
					entity_move(u32(i), entity, new_position, scene)
				} 
				else
				{
					fmt.println("COCALCOL")
					opposite_position := Vec2{-entity.direction.x, -entity.direction.y} + entity.position
					if is_wall(opposite_position, scene^) || !cell_empty_or_grounded(opposite_position, scene) do entity.moved = true
					else do entity.direction = {-entity.direction.x, -entity.direction.y}
				}
			}
		}
	}

	new_position = entity.position + entity.direction

	if !entity.moved do	entity_move(u32(i), entity, new_position, scene)

}

static_action :: proc(position: Vec2, scene: ^Scene)
{
	cell := cell_get_by_pos(position, scene)

	if position.x == 8 do fmt.println(position)
	if cell.entity_count == 0 do return
	for i in 0..<cell.entity_count
	{
		id := cell.entities_id[i]
		entity := entity_get(id, scene)

		if .PRESSABLE in entity.flags
		{
			_, _, count := entities_get_from_pos(entity.position, scene)
			linked_id := entity.class.(Object).linked_entity
			linked_entity := entity_get(linked_id, scene)

			switch linked_entity.class.(Object).link_type
			{
				case .SET_ACTIVE:
					state := linked_entity.active
					entity_set_active(linked_id, !state, scene)

				case .SET_FALLTHROUGH:
					state := .FALLTHROUGH in linked_entity.flags
					entity_set_fallthrough(linked_id, state, scene)
			}

		}
		
		if .FALLTHROUGH in entity.flags
		{
			for j in 0..<cell.entity_count
			{ 
				new_id := cell.entities_id[j]
				if new_id == id do continue
				entity_kill(new_id, scene)
			}
			break
		}
	}

}
// s_static_actions :: proc(scene: ^Scene)
// {
// 	for i in PLAYER_INDEX..<scene.entity_cout
// 	{
// 		entity := entity_get(u32(i), scene)
// 		if entity.direction == {0, 0} 
// 		{
// 			if .STOMPABLE in entity.flags
// 			{
// 				_, _, count := entities_get_from_pos(entity.position, scene)
//
// 				linked_entity := entity.class.(Object).linked_entity
// 				if count > 1 { entity_set_fallthrough(linked_entity, true, scene) } 
// 				else { entity_set_fallthrough(linked_entity, false, scene) }
// 			}
//
// 			// if .FALLTHROUGH in entity.flags
// 			// {
// 			// 	e, ids, count := entities_get_from_pos(entity.position, scene)
// 			// 	fmt.println("CELL" , cell_get_by_pos(entity.position, scene))
// 			// 	fmt.println("COUNT:", count)
// 			// 	fmt.println("IDS", ids)
// 			// 	if count > 1 do out("BIEN")
// 			// }
// 			//
//
// 			if .PRESSABLE in entity.flags
// 			{
// 				_, _, count := entities_get_from_pos(entity.position, scene)
// 				linked_entity_id := entity.class.(Object).linked_entity
// 				linked_entity := entity_get(linked_entity_id, scene)
//
//
// 				switch linked_entity.class.(Object).link_type {
// 					case .SET_ACTIVE:
// 						if count > 1 { entity_set_active(linked_entity_id, true, scene) } 
// 						else { entity_set_active(linked_entity_id, false, scene) }
// 					case .SET_FALLTHROUGH:
// 						if count > 1 { entity_set_fallthrough(linked_entity_id, true, scene) } 
// 						else { entity_set_fallthrough(linked_entity_id, false, scene) }
// 				}
// 			} 
//
// 			continue
// 		}
// 	}
// }

