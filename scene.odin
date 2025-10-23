package main

import "core:fmt"
import os"core:os/os2"
import "core:strings"
import "core:strconv"
import "core:path/filepath"

load_scene :: proc(scene_name: string, scene: ^Scene)
{
	assert(filepath.long_ext(scene_name)== ".scene")

	data, err := os.read_entire_file(scene_name, context.temp_allocator)
	assert(err==nil)

	scene_description := string(data)
	scene.name = "UNTITLED"
	scene.entity_count = 1

	current_row := 0
	for &line, i in strings.split_lines(scene_description, context.temp_allocator)
	{
		if line == "" do continue
		if strings.starts_with(line, "\"") 
		{
			scene.name = strings.trim(line, "\"")
			continue
		}

		if starts_with_num(line)
		{
			if strings.contains(line, "x") 
			{
				scene.rows, scene.columns = extract_board_size(line) 	
				continue
			}

			id, ok := parse_num_from_line_start(&line)
			if !ok do out()

			class, fields_left := parse_class_from_line(&line)
			entity, entity_id:= entity_new(class, scene)
			entity_add(entity, entity_id, scene)
			assert(u32(id) == entity_id)

			if fields_left do parse_fields_from_line(&line, entity_id, scene)
			continue
		}
		parse_board_line(strings.trim_space(line), &current_row, scene)
	}
}


parse_fields_from_line :: proc(line: ^string, entity_id: u32, scene: ^Scene)
{
	if len(line) == 0 do return

	// if -1 we split directly, if not later we will run function with offset
	fields, err := strings.split(line^, "-", context.temp_allocator)
	if err != nil do os.exit(1)
	
	for &field in fields
	{
		field = strings.trim_space(field)
		parts := strings.split(field, "=", context.temp_allocator)
		switch parts[0]{
		case "dir":
			nums := strings.split(strings.trim(parts[1], "{}"), ",", context.temp_allocator)
			if len(nums) > 2 do out()
			dir: Vec2
			ok: bool
			dir.x, ok = strconv.parse_f32(nums[0]); assert(ok)
			dir.y, ok = strconv.parse_f32(nums[1]); assert(ok)

			entity_set_dir(entity_id, dir, scene)
		case "link":
			val, ok := strconv.parse_int(parts[1])
			if !ok do out()
			entity_set_link(entity_id, u32(val), scene)

		case "active":
			val := parts[1]=="f" ? false : true
			entity_set_active(entity_id, val, scene)
		}
	}

}

parse_class_from_line :: proc(line: ^string)-> (kind: E_ENTITY,  fields_left: bool)
{
	entity_string := strings.trim(line^, "{")
	line^ = line[1:]
	pointer := 0
	for ; pointer < len(entity_string); pointer += 1
	{
		char := entity_string[pointer] 
		if  char == ','{
			fields_left = true
			break
		} 
		else if char == '}'
		{
			fields_left = false
			break
		}
	}

	fmt.println("$$", entity_string[:pointer])
	switch entity_string[:pointer]
	{
		case "PLAYER":
			kind = .PLAYER
		case "GOAL":
			kind = .GOAL
		case "BUTTON":
			kind = .BUTTON
		case "BOX":
			kind = .BOX
		case "CROCO":
			kind = .CROCO
	}

	if fields_left do line^ = line[pointer+1:len(line)-1]; else do line^ = ""
	return
}





@(private)
extract_board_size :: proc(line: string)-> (int, int)
{	
	using strconv
	values, err := strings.split(line, "x", context.temp_allocator)
	assert(err==nil)

	return atoi(values[0]), atoi(values[1])
}

parse_board_line :: proc(line: string, current_row: ^int, scene: ^Scene)
{
	
	column := 0
	row := current_row^
	for char in line
	{
		switch char
		{
		case '0':
			scene.board[row][column].bg_texture = scene.textures[.MM]  
		case '┌': 
			scene.board[row][column].bg_texture = scene.textures[.TL]  
			scene.board[row][column].wall = true
		case '└':
			scene.board[row][column].bg_texture = scene.textures[.BL]
			scene.board[row][column].wall = true
		case '┐':
			scene.board[row][column].bg_texture = scene.textures[.TR]
			scene.board[row][column].wall = true
		case '┘':
			scene.board[row][column].bg_texture = scene.textures[.BR]
			scene.board[row][column].wall = true
		case '┴':
			scene.board[row][column].bg_texture = scene.textures[.BM]
			scene.board[row][column].wall = true 
		case '┬':
			scene.board[row][column].bg_texture = scene.textures[.TM]
			scene.board[row][column].wall = true 
		case '├':
			scene.board[row][column].bg_texture = scene.textures[.ML]
			scene.board[row][column].wall = true 
		case '┤':
			scene.board[row][column].bg_texture = scene.textures[.MR]
			scene.board[row][column].wall = true 
		case '$':
			scene.board[row][column].bg_texture = scene.textures[.IBL]
			scene.board[row][column].wall = true 
		case '(':
			scene.board[row][column].bg_texture = scene.textures[.IBR]
			scene.board[row][column].wall = true 
		case '-':
			scene.board[row][column].no_bg = true
		case 'A'..='Z':
			entity_id :=  char - 'A' + 10
			count := scene.board[row][column].entity_count
			scene.board[row][column].entities_id[count] = u32(entity_id)
			scene.entities[entity_id].position = Vec2{f32(column), f32(row)}
			scene.board[row][column].bg_texture = scene.textures[.MM]  
			scene.board[row][column].entity_count += 1
		case:
			entity_id, ok := rune_to_int(char); assert(ok)
			
			count := scene.board[row][column].entity_count
			scene.board[row][column].entities_id[count] = u32(entity_id)
			
			scene.entities[entity_id].position = Vec2{f32(column), f32(row)}

			scene.board[row][column].bg_texture = scene.textures[.MM]  

			scene.board[row][column].entity_count += 1
		}

		column += 1
	}
	current_row^ += 1
}

starts_with_num :: proc(line: string)-> bool
{
	if len(line) == 0 do return false

	val := int(line[0])
	if val < 48 || val > 57 do return false

	return true
}


@(private)
parse_num_from_line_start :: proc(line: ^string)->(int, bool)
{
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	
	count := 0
	for char in line
	{
		_ , ok := rune_to_int(char)
		if !ok {
			break
		}

		strings.write_rune(&sb, char)
		count +=1
	}
	
	line^ = line[count:]
	return strconv.parse_int(strings.to_string(sb))
}



rune_to_int :: proc(char: rune)-> (int, bool)
{
	val := int(char)-48
	if val > 9 || val < 0 do return 0, false
	return val, true
}
