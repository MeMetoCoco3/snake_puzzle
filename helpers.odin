package main
import "core:c"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import stbi "vendor:stb/image"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Color:: [4]byte

VBO :: u32
VAO :: u32
EBO :: u32
FBO :: u32
RBO :: u32

WIDTH  :: 1200
HEIGHT :: 1000

delta_time: f32
last_frame: f32

set_vec2 :: proc(program: u32, loc: cstring, val: Vec2) 		   { gl.Uniform2f(gl.GetUniformLocation(program, loc), val.x, val.y) }
set_vec3 :: proc(program: u32, loc: cstring, val: Vec3) 		   { gl.Uniform3f(gl.GetUniformLocation(program, loc), val.x, val.y, val.z) }
set_vec4 :: proc(program: u32, loc: cstring, val: Vec4) 		   { gl.Uniform4f(gl.GetUniformLocation(program, loc), val.x, val.y, val.z, val.y) }
set_mat4 :: proc(program: u32, loc: cstring, val: ^matrix[4, 4]f32) { gl.UniformMatrix4fv(gl.GetUniformLocation(program, loc), 1, gl.FALSE, &val[0, 0]) }


init_glfw :: proc() 
{
	glfw.Init()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.DEPTH_BITS, 24)


	Window.handler = glfw.CreateWindow(WIDTH, HEIGHT, "LEARN", nil, nil)
	assert(Window.handler != nil)
	Window.w = WIDTH
	Window.h = HEIGHT

	glfw.MakeContextCurrent(Window.handler)
	// glfw.SetInputMode(Window.handler, glfw.CURSOR, glfw.CURSOR_DISABLED)

	glfw.SetFramebufferSizeCallback(Window.handler, framebuffer_size_callback)
	// glfw.SetCursorPosCallback(Window.handler, mouse_callback)
	// glfw.SetScrollCallback(Window.handler, scroll_callback)

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
	gl.Viewport(0, 0, WIDTH, HEIGHT)
}

end_glfw :: proc() 
{
	glfw.DestroyWindow(Window.handler)
	glfw.Terminate()
}

get_offset :: proc(rows, columns: i32)-> (i32, i32)
{
	offset_x := Window.w/2 - (columns/2)*CELL_SIZE
	offset_y := Window.h/2 - (rows/2)*CELL_SIZE
	return offset_x, offset_y
}

set_grid :: proc(rows: i32, columns: i32, offset_x: i32=0, offset_y: i32=0)-> VAO
{
	VecData:: struct
	{
		vertex: Vec3,
		uv: Vec2
	}

	points : [MAX_GEOMETRY_POINTS_PER_BOARD]VecData
	n: int

	GRID_WIDTH := columns * CELL_SIZE + offset_x
	GRID_HEIGHT := rows * CELL_SIZE + offset_y


	for j := offset_y; j < GRID_HEIGHT; j += CELL_SIZE 
	{
		for i := offset_x; i < GRID_WIDTH; i += CELL_SIZE 
		{
			points[n] = VecData{vertex = {f32(i), f32(j), 0}, uv = {0, 0}}
			points[n+1] = VecData{vertex = {f32(i+CELL_SIZE), f32(j), 0}, uv =  {1, 0}}
			points[n+2] = VecData{vertex = {f32(i), f32(j+CELL_SIZE), 0},  uv =  {0, 1}}
			points[n+3] = VecData{vertex = {f32(i+CELL_SIZE), f32(j), 0},  uv =  {1, 0}}
			points[n+4] = VecData{vertex = {f32(i+CELL_SIZE), f32(j+CELL_SIZE), 0},  uv =  {1, 1}}
			points[n+5] = VecData{vertex = {f32(i), f32(j+CELL_SIZE), 0},  uv =  {0, 1}}
			n += 6
		}
	}

	vbo: VBO
	vao: VAO

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo) 
	gl.BufferData(gl.ARRAY_BUFFER, size_of(points), &points, gl.STATIC_DRAW)

	gl.VertexAttribPointer \
	(
		index = 0,
		size = 3,
		type = gl.FLOAT,
		normalized = gl.FALSE,
		stride = size_of(VecData),
		pointer = 0,
	)
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(
		index = 1,
		size = 2,
		type = gl.FLOAT,
		normalized = gl.FALSE,
		stride = size_of(VecData),
		pointer = offset_of(VecData, uv),
	)
	gl.EnableVertexAttribArray(1)

	gl.BindVertexArray(0)

	return vao
}

load_shaders :: proc(vertex_path, fragment_path:string,  geometry_path: string = "") -> u32 
{
    program := gl.CreateProgram()

    vs := gl.CreateShader(gl.VERTEX_SHADER)
    vs_src, _ := os.read_entire_file_or_err(vertex_path, context.temp_allocator)
    cvs: cstring = strings.clone_to_cstring(transmute(string)vs_src, context.temp_allocator)
    gl.ShaderSource(vs, 1, &cvs, nil)
    gl.CompileShader(vs)

    success: i32
    gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success)
    if success == 0 
	{
        buf: [512]u8
        gl.GetShaderInfoLog(vs, 512, nil, &buf[0])
        log.infof("Vertex shader compile error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    fs := gl.CreateShader(gl.FRAGMENT_SHADER)
    fs_src, _ := os.read_entire_file_or_err(fragment_path, context.temp_allocator)
    cfs: cstring = strings.clone_to_cstring(transmute(string)fs_src, context.temp_allocator)
    gl.ShaderSource(fs, 1, &cfs, nil)
    gl.CompileShader(fs)
    gl.GetShaderiv(fs, gl.COMPILE_STATUS, &success)
    if success == 0 
	{
        buf: [512]u8
        gl.GetShaderInfoLog(fs, 512, nil, &buf[0])
        log.infof("Fragment shader compile error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    gs: u32 = 0
    if geometry_path != "" 
	{
        gs = gl.CreateShader(gl.GEOMETRY_SHADER)
        gs_src, _ := os.read_entire_file_or_err(geometry_path, context.temp_allocator)
        cgs: cstring = strings.clone_to_cstring(transmute(string)gs_src, context.temp_allocator)
        gl.ShaderSource(gs, 1, &cgs, nil)
        gl.CompileShader(gs)
        gl.GetShaderiv(gs, gl.COMPILE_STATUS, &success)
        if success == 0 {
            buf: [512]u8
            gl.GetShaderInfoLog(gs, 512, nil, &buf[0])
            log.infof("Geometry shader compile error:\n%v", transmute(string)buf[:])
            os.exit(1)
        }
        gl.AttachShader(program, gs)
    }

    gl.AttachShader(program, vs)
    gl.AttachShader(program, fs)
    gl.LinkProgram(program)

    gl.GetProgramiv(program, gl.LINK_STATUS, &success)
    if success == 0 
{
        buf: [512]u8
        gl.GetProgramInfoLog(program, 512, nil, &buf[0])
        log.infof("Shader program link error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    // Cleanup
    gl.DeleteShader(vs)
    gl.DeleteShader(fs)
    if geometry_path != "" 
	{
        gl.DeleteShader(gs)
    }

    return program
}


load_texture :: proc(name: string, key: E_TEXTURE, textures: ^map[E_TEXTURE]u32)
{
	id: u32
	gl.GenTextures(1, &id)
	
	width, height, n_components: i32

	c_path := strings.clone_to_cstring(name, context.temp_allocator)

	data  := stbi.load(c_path, &width, &height, &n_components, 0)
	if (data!=nil) 
	{
		format : u32
		switch n_components
		{
		case 1:
			format = gl.RED
		case 3:
			format = gl.RGB
		case 4:
			format = gl.RGBA
		case:
			log.infof("Not defined number of components: %v, for image: %v", n_components, name)
			os.exit(1)
		}

		gl.BindTexture(gl.TEXTURE_2D, id)
		gl.TexImage2D(gl.TEXTURE_2D, 0, i32(format), width, height, 0, format, gl.UNSIGNED_BYTE, data)
		gl.GenerateMipmap(gl.TEXTURE_2D)

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	}
	else
	{
		log.infof("Error loading texture '%v'.", name)
		log.infof("From path: %s", c_path)
		os.exit(1)
	}

	textures[key] = id

	stbi.image_free(data)
	return
}


// Callback function on window resize.
framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) 
{
	Window.w = width
	Window.h = height
	gl.Viewport(0, 0, width, height)
}

out :: proc(line:any=0, loc := #caller_location) 
{
	fmt.println(line)
	fmt.printf("We are going out on line: %v", loc)
	os.exit(1)
}

s_collide :: proc(scene: ^Scene)
{
	for i in 0..<scene.entity_count
	{
		entity := entity_get(u32(i), scene)
		if entity.direction == {0, 0} do continue
		entity_set_moved(u32(i), false, scene)
		new_position := entity.position + entity.direction
		if .ENEMY in entity.flags do fmt.println("HERE")
		if !is_out(new_position, i32(scene.columns), i32(scene.rows))
		{
			if !is_wall(new_position, scene^)
			{
				entities, entities_ids, e_count := entities_get_from_pos(new_position, scene)	

				for j := i32(e_count)-1; j >= 0; j -=1
				{
					if entities_ids[j] > 0 && entity_get_active(entities_ids[j], scene)
					{
						if .WIN in entities[j].flags do glfw.SetWindowShouldClose(Window.handler, true)
						if .ENEMY in entities[j].flags do glfw.SetWindowShouldClose(Window.handler, true)
						if .PRESSABLE in entities[j].flags
						{
							linked_entity := entities[j].class.(Object).linked_entity
							entity_set_active(linked_entity, true, scene)
							entity_move(u32(i), entity.position, new_position, scene)
							entity_set_moved(u32(i), true, scene)
						}
						
						if .PUSHABLE in entities[j].flags
						{
							pushed_new_position := new_position + entity.direction
							ok_to_push := cell_empty_or_grounded(pushed_new_position, scene)
							if !is_wall(new_position+entity.direction, scene^) && ok_to_push
							{
								entity_move(entities_ids[j], new_position, pushed_new_position, scene)
								entity_move(u32(i), entity.position, new_position, scene)
								entity_set_moved(u32(i), true, scene)
							} 
							else do entity_set_dir(u32(i), {-entity.direction.x, -entity.direction.y}, scene)
						}
						fmt.println("JAMON!")
						if PLAYER_INDEX == entities_ids[j]
						{
							fmt.println("JAMON!")
							if .ENEMY in entity.flags do glfw.SetWindowShouldClose(Window.handler, true) 
						}




			

						if .STOMPABLE in entities[j].flags
						{

						}

					}
				}
			} 
			else 
			{
				if .MOVER in entity.flags do entity_set_dir(u32(i), { -entity.direction.x, -entity.direction.y }, scene)
				if PLAYER_INDEX == i do entity_set_dir(u32(i), {0, 0}, scene)
			}
			continue
		}
	}
	fmt.println()
}

entity_set_moved :: proc(id: u32, state: bool, scene: ^Scene){scene.entities[id].moved = state}

s_static_acctions :: proc(scene: ^Scene)
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



// add_dir_to_pos :: proc(pos: Vec2, dir: Vec2)-> Vec2
// {
// 	return Vec2{pos.x + dir.y, pos.y + dir.x}
// }

// WARN: s_move moves only entities which move does not affect others.
// Moves that affect other entities are done on collision system because the orther in which is done matters
s_move :: proc(scene: ^Scene)
{
	for i in 0..<scene.entity_count
	{
		entity := entity_get(u32(i), scene)
		if entity.direction != {0, 0} && !entity.moved 
		{
			entity_move(u32(i), entity.position, entity.position + entity.direction, scene)
			// if .MOVER not_in entity.flags do entity_set_dir(u32(i), {0, 0})
		}
	}
}

is_wall :: proc(pos: Vec2, scene: Scene)->bool { return scene.board[int(pos.y)][int(pos.x)].wall }

 
MoveRest :: proc(){}

is_out :: proc(pos: Vec2, rows, cols: i32)->bool
{
	if pos.y < 0 || pos.y >= f32(rows) do return true
	if pos.x < 0 || pos.x >= f32(cols) do return true
	return false
}

board_set :: proc(scene: ^Scene)
{
	fmt.println("AKI", scene.rows, scene.columns)
	scene.rows = 10
	scene.columns = 10
	for i in 0..<scene.rows
	{
		for j in 0..<scene.columns
		{
			cell := &Game.scene.board[i][j]
			if j == 0 && (i > 0 && i < 9)
			{
				cell.bg_texture = scene.textures[.ML]
				cell.wall = true
			}
			else if j == 9 && (i > 0 && i < 9)
			{
				cell.bg_texture = scene.textures[.MR]
				cell.wall = true
			}
			else if i == 0 && (j > 0 && j < 9)
			{
				cell.bg_texture = scene.textures[.TM]
				cell.wall = true
			}
			else if i == 9 && (j > 0 && j < 9)
			{
				cell.bg_texture = scene.textures[.BM]
				cell.wall = true
			}
			else if i < 9 && i > 0 && j < 9 && j > 0
			{
				cell.bg_texture = scene.textures[.MM]
			} 
			else{ cell.wall = false }
		}
	}

	Game.scene.board[0][0].bg_texture = scene.textures[.TL]
	Game.scene.board[0][9].bg_texture = scene.textures[.TR]
	Game.scene.board[9][0].bg_texture = scene.textures[.BL]
	Game.scene.board[9][9].bg_texture = scene.textures[.BR]
}

get_pixel_from_image:: proc(name:string, x:i32, y:i32)-> (color: Color){
	width, height, n_components: i32

	c_path := strings.clone_to_cstring(name, context.temp_allocator)

	data  := stbi.load(c_path, &width, &height, &n_components, 0)
	if (data!=nil) 
	{
	format : u32
		switch n_components
		{
		case 1:
			log.infof("Not enough info:  for image: %v, number of components: %v", name,  n_components)
			os.exit(1)
		case 3:
			format = gl.RGB
		case 4:
			format = gl.RGBA
		case:
			log.infof("Not defined number of components: %v, for image: %v", n_components, name)
			os.exit(1)
		}

		index := (y * width + x) * n_components
		color.x = data[0+index]
		color.y = data[1+index]
		color.z = data[2+index]

		if format == gl.RGBA do color.w = data[3+index]

		stbi.image_free(data)
	}
	else
	{
		log.infof("Error loading texture '%v'.", name)
		log.infof("From path: %s", c_path)
		os.exit(1)
	}

	return
}

