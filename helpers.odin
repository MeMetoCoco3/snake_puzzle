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

VBO :: u32
VAO :: u32
EBO :: u32
FBO :: u32
RBO :: u32

WIDTH :: 1200
HEIGHT :: 1000

delta_time: f32
last_frame: f32

set_vec3 :: proc(program: u32, loc: cstring, val: Vec3) 		   { gl.Uniform3f(gl.GetUniformLocation(program, loc), val.x, val.y, val.z) }
set_vec4 :: proc(program: u32, loc: cstring, val: Vec4) 		   { gl.Uniform4f(gl.GetUniformLocation(program, loc), val.x, val.y, val.z, val.y) }
set_mat4 :: proc(program: u32, loc: cstring, val: ^matrix[4, 4]f32) { gl.UniformMatrix4fv(gl.GetUniformLocation(program, loc), 1, gl.FALSE, &val[0, 0]) }

process_input :: proc(window: glfw.WindowHandle) {
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
		}
	} 
	else { Game.keys_down[glfw.KEY_UP] = false }

	if glfw.GetKey(window, glfw.KEY_DOWN) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_DOWN]
		{
			entity_set_dir(PLAYER_INDEX, {0, 1})
			Game.keys_down[glfw.KEY_DOWN] = true
		}
	}
	else { Game.keys_down[glfw.KEY_DOWN] = false }

	if glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_LEFT]
		{
			entity_set_dir(PLAYER_INDEX, {-1, 0})
			Game.keys_down[glfw.KEY_LEFT] = true
		}
	} 
	else { Game.keys_down[glfw.KEY_LEFT] = false }

	if glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS  
	{
		if !Game.keys_down[glfw.KEY_RIGHT]
		{
			entity_set_dir(PLAYER_INDEX, {1, 0})
			Game.keys_down[glfw.KEY_RIGHT] = true
		}
	} 
	else { Game.keys_down[glfw.KEY_RIGHT] = false }
}


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

MAX_NUM_CELLS_PER_GRID :: 6 * 20 * 20
MAX_NUM_INDEXES :: 100
set_grid :: proc(rows: i32, columns: i32, offset_x: i32=0, offset_y: i32=0)-> VAO
{
	VecData:: struct
	{
		vertex: Vec3,
		uv: Vec2
	}

	points : [MAX_NUM_CELLS_PER_GRID]VecData
	n: int

	GRID_WIDTH := columns * CELL_SIZE + offset_x
	GRID_HEIGHT := rows * CELL_SIZE + offset_y

	for i := offset_x; i < GRID_WIDTH; i += CELL_SIZE 
	{
		for j := offset_y; j < GRID_HEIGHT; j += CELL_SIZE 
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
    vs_src, _ := os.read_entire_file_or_err(vertex_path)
    cvs: cstring = strings.clone_to_cstring(transmute(string)vs_src)
    gl.ShaderSource(vs, 1, &cvs, nil)
    gl.CompileShader(vs)

    success: i32
    gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success)
    if success == 0 
	{
        buf: [512]u8
        gl.GetShaderInfoLog(vs, 512, nil, &buf[0])
        fmt.printfln("Vertex shader compile error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    fs := gl.CreateShader(gl.FRAGMENT_SHADER)
    fs_src, _ := os.read_entire_file_or_err(fragment_path)
    cfs: cstring = strings.clone_to_cstring(transmute(string)fs_src)
    gl.ShaderSource(fs, 1, &cfs, nil)
    gl.CompileShader(fs)
    gl.GetShaderiv(fs, gl.COMPILE_STATUS, &success)
    if success == 0 
	{
        buf: [512]u8
        gl.GetShaderInfoLog(fs, 512, nil, &buf[0])
        fmt.printfln("Fragment shader compile error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    gs: u32 = 0
    if geometry_path != "" 
	{
        gs = gl.CreateShader(gl.GEOMETRY_SHADER)
        gs_src, _ := os.read_entire_file_or_err(geometry_path)
        cgs: cstring = strings.clone_to_cstring(transmute(string)gs_src)
        gl.ShaderSource(gs, 1, &cgs, nil)
        gl.CompileShader(gs)
        gl.GetShaderiv(gs, gl.COMPILE_STATUS, &success)
        if success == 0 {
            buf: [512]u8
            gl.GetShaderInfoLog(gs, 512, nil, &buf[0])
            fmt.printfln("Geometry shader compile error:\n%v", transmute(string)buf[:])
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
        fmt.printfln("Shader program link error:\n%v", transmute(string)buf[:])
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


load_texture :: proc(name: string, key: E_TEXTURE)
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
			fmt.printfln("Not defined number of components: %v, for image: %v", n_components, name)
			os.exit(1)
		}

		gl.BindTexture(gl.TEXTURE_2D, id)

		gl.TexImage2D(gl.TEXTURE_2D, 0, i32(format), width, height, 0, format, gl.UNSIGNED_BYTE, data)
		gl.GenerateMipmap(gl.TEXTURE_2D)

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

		stbi.image_free(data)
	}
	else
	{
		fmt.printfln("Error loading texture '%v'.", name)
		fmt.printfln("From path: %s", c_path)
		os.exit(1)
	}

	textures[key] = id
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


s_collide :: proc()
{
	// INFO: First we move Player
	player := entity_get(PLAYER_INDEX)
	new_position := player.position + player.direction 
	if !is_out(new_position, len(Game.board), len(Game.board[0])) && player.direction != {0, 0} 
	{
		entities, entities_ids, e_count := entities_get_from_pos(new_position)	

		for i in 0..<e_count
		{
			if entities_ids[i] > 1 
			{
				log.infof("Player collide with: %v, on %v ", entities[i], new_position)
				if .WIN in entities[i].flags
				{
					fmt.println("JAMON")
				}
			}
		}
		if is_wall(new_position) do entity_move(PLAYER_INDEX, player.position, new_position)
	}
	entity_set_dir(PLAYER_INDEX, {0, 0})

	// TODO: Move rest 
}

is_wall :: proc(pos: Vec2)->bool
{
	return Game.board[int(pos.x)][int(pos.y)].wall

}

 
MoveRest :: proc(){}

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



cell_is_empty :: proc(cell: Cell)-> bool{ return cell.entity_count == 0 }

is_out :: proc(pos: Vec2, rows, cols: i32)->bool
{
	if pos.y < 0 || pos.y >= f32(cols) do return true
	if pos.x < 0 || pos.x >= f32(rows) do return true
	return false
}

set_board :: proc()
{
	for i in 0..<ROWS
	{
		for j in 0..<COLUMNS
		{
			cell := &Game.board[i][j]
			if j == 1 && (i > 1 && i < 8)
			{
				cell.bg_texture = textures[.TM]
				cell.wall = true
				continue
			}

			if j == 8 && (i > 1 && i < 8)
			{
				cell.bg_texture = textures[.BM]
				cell.wall = true
				continue
			}

			if i == 1 && (j > 1 && j < 8)
			{
				cell.bg_texture = textures[.ML]
				cell.wall = true
				continue
			}

			if i == 8 && (j > 1 && j < 8)
			{
				cell.bg_texture = textures[.MR]
				cell.wall = true
				continue
			}

			if i < 8 && i > 1 && j < 8 && j > 1
			{
				cell.bg_texture = textures[.MM]
				cell.wall = true
				continue
			} 
			else { cell.bg_texture = textures[.DIRTY_PIG] }
		}
	}

	Game.board[1][1].bg_texture = textures[.TL]
	Game.board[1][1].wall = true
	Game.board[1][8].bg_texture = textures[.BL]
	Game.board[1][8].wall = true
	Game.board[8][1].bg_texture = textures[.TR]
	Game.board[8][1].wall = true
	Game.board[8][8].bg_texture = textures[.BR]
	Game.board[8][8].wall = true

}
