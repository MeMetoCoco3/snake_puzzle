package main

import "core:fmt"
import "vendor:glfw"

///////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////

s_collide :: proc(scene: ^Scene)
{
	for i in 0..<scene.entity_count
	{
		entity := entity_get(u32(i), scene)

		if is_player(u32(i)) do s_collide_player(u32(i), scene) 
		else if is_enemy(entity) do s_collide_enemy(u32(i), scene)
	}
}

@(private)
s_collide_player :: proc(i: u32, scene: ^Scene)
{
	entity := entity_get(u32(i), scene)
	entity.moved = false
	
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

			if .ENEMY in entities[j].flags do glfw.SetWindowShouldClose(Window.handler, true)
			if .PRESSABLE in entities[j].flags
			{
				linked_entity := entities[j].class.(Object).linked_entity
				entity_set_active(linked_entity, true, scene)

				entity_move(u32(i), entity.position, new_position, scene)

				entity.position = new_position
				entity_update(u32(i), entity, scene)
				entity.moved = true
				continue
			}
			
			if .PUSHABLE in entities[j].flags
			{
				pushed_new_position := entity.position + (2*entity.direction)
				ok_to_push := cell_empty_or_grounded(pushed_new_position, scene)
				if !is_wall(new_position+entity.direction, scene^) && ok_to_push
				{
					entity_move(entities_ids[j], new_position, pushed_new_position, scene)
					entity_move(u32(i), entity.position, new_position, scene)

					entity.position = new_position
					entity_update(u32(i), entity, scene)
					entity.moved = true
				} 
				else 
				{
					return
				}
				continue
			}
		}
	}
	if !entity.moved 
	{
		entity_move(u32(i), entity.position, new_position, scene)
		entity.position = new_position
	}
	
	entity_update(u32(i), entity, scene)
}

@(private)
s_collide_enemy :: proc(i: u32, scene: ^Scene)
{
	entity := entity_get(u32(i), scene)
	entity.moved = false

	if entity.direction == {0, 0} do return

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
			if is_player(entities_ids[j]) do glfw.SetWindowShouldClose(Window.handler, true) 

			if .PUSHABLE in entities[j].flags
			{
				pushed_new_position := entity.position + (2 * entity.direction)
				ok_to_push := cell_empty_or_grounded(pushed_new_position, scene)
				if !is_wall(pushed_new_position, scene^) && ok_to_push
				{
					entity_move(entities_ids[j], entities[j].position, pushed_new_position, scene)
					entity_move(u32(i), entity.position, new_position, scene)
					
					entity.position = new_position
					entity_update(u32(i), entity, scene)
					entity.moved = true
				} 
				else
				{
					opposite_position := Vec2{-entity.direction.x, -entity.direction.y} + entity.position
					if is_wall(opposite_position, scene^) || !cell_empty_or_grounded(opposite_position, scene) do entity.moved = true
					else do entity.direction = {-entity.direction.x, -entity.direction.y}
				}
			}
		}
	}

	if !entity.moved 
	{
		new_position = entity.position + entity.direction
		entity_move(u32(i), entity.position, new_position, scene)
		entity.position = new_position
	}

	entity_update(u32(i), entity, scene)
}

entity_get_moved :: proc(id: u32, scene: ^Scene)-> bool {return scene.entities[id].moved }
entity_set_moved :: proc(id: u32, state: bool, scene: ^Scene){scene.entities[id].moved = state}

s_static_actions :: proc(scene: ^Scene)
{
	for i in 0..<scene.entity_count
	{
		entity := entity_get(u32(i), scene)
		if entity.direction == {0, 0} 
		{
			if .PRESSABLE in entity.flags
			{
				_, _, count := entities_get_from_pos(entity.position, scene)

				linked_entity := entity.class.(Object).linked_entity
				if count > 1 { entity_set_active(linked_entity, true, scene) } 
				else { entity_set_active(linked_entity, false, scene) }
			} 
			continue
		}
	}
}

//
// s_move :: proc(scene: ^Scene)
// {
// 	for i in 0..<scene.entity_count
// 	{
// 		entity := entity_get(u32(i), scene)
// 		if entity.direction != {0, 0} && !entity.moved 
// 		{
// 			entity_move(u32(i), entity.position, entity.position + entity.direction, scene)
// 		} else do entity_set_moved(u32(i), false, scene)
// 	}
// }

