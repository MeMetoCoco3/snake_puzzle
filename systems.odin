package main


s_collide :: proc(scene: ^Scene)
{
	for i in 0..<scene.entity_count
	{
		entity := entity_get(u32(i), scene)
		if entity.direction == {0, 0} do continue
		entity_set_moved(u32(i), false, scene)

		new_position := entity.position + entity.direction

		if is_player(u32(i)) do s_collide_player(u32(i), entity, new_position, scene) 
		else if is_enemy(entity) do s_collide_enemy(u32(i), entity, new_position, scene)

		continue
	}
}


