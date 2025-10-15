package main
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import ai "shared:assimp/import"
import gl "vendor:OpenGL"
import "vendor:glfw"
import stbi "vendor:stb/image"

ASSETS_PATH :: "assets/"

MIN_NUM_MESHES :: 10
MIN_NUM_VERTICES :: 1024
MIN_NUM_INDICES :: 1024
MIN_NUM_TEXTURES :: 10

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

VBO :: u32
VAO :: u32
EBO :: u32
FBO :: u32
RBO :: u32

TexID :: u32

Vertex :: struct #packed{
	position:  Vec3,
	normal:    Vec3,
	tex_coord: Vec2,
}

TEXTURE_TYPE :: enum {
	DIFFUSE,
	SPECULAR,
}

Texture :: struct {
	id:        u32,
	type:      TEXTURE_TYPE,
	file_name: string,
}

Mesh :: struct {
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u32,
	textures: [dynamic]Texture,
	vao:      VAO,
	vbo:      VBO,
	ebo:      EBO,
}

Model :: struct {
	relative_path: string,
	meshes:        [dynamic]Mesh,
}


VS		   :: "vertex.glsl"
FS		   :: "fragment.glsl"
VS_LIGHT   :: "light_vertex.glsl"
FS_LIGHT   :: "light_fragment.glsl"
FS_SKY     :: "sky_frag.glsl"
VS_SKY     :: "sky_vert.glsl"


SVS 	   :: "vertex_screen.glsl"
SFS        :: "frag_screen.glsl"
OUTLINE_FS :: "fragmentSingleColor.glsl"


FOV :: 49
WIDTH :: 1200
HEIGHT :: 1000

MOVE_SPEED :: 10

Camera :: struct {
	position: Vec3,
	target:   Vec3,
	up:       Vec3,
	yaw:      f32,
	pitch:    f32,
	roll:     f32,
}

Material :: struct {
	ambient:   Vec3,
	diffuse:   Vec3,
	specular:  Vec3,
	shininess: f32,
}

mat := Material {
	ambient   = {1, 0.5, 0.31},
	diffuse   = {1, 0.5, 0.31},
	specular  = {0.5, 0.5, 0.5},
	shininess = 32,
}

DirectionLight :: struct {
	direction: Vec3,
	ambient:   Vec3,
	diffuse:   Vec3,
	specular:  Vec3,
	intensity: f32,
}

dirLight := DirectionLight {
	ambient   = {0.2, 0.2, 0.2},
	diffuse   = {0.8, 0.8, 0.8},
	specular  = {1, 1, 1},
	direction = {0, 0, -1},
	intensity = 1,
}


PointLight :: struct {
	position:  Vec3,
	ambient:   Vec3,
	diffuse:   Vec3,
	specular:  Vec3,
	constant:  f32,
	linear:    f32,
	quadratic: f32,
	intensity: f32,
}

point_light := PointLight {
	ambient   = {0.2, 0.2, 0.2},
	diffuse   = {0.8, 0.8, 0.8},
	specular  = {1, 1, 1},
	linear    = 0.09,
	constant  = 1,
	quadratic = 0.032,
	intensity = 1,
}
NUM_POINT_LIGHT :: 4
point_lights := [NUM_POINT_LIGHT]PointLight{}

point_light_positions := [NUM_POINT_LIGHT]Vec3 {
	{0.7, 0.2, 2},
	{2.3, -3.3, -4},
	{-4, 2, -12},
	{0, 0, -3},
}


SpotLight :: struct {
	position:      Vec3,
	ambient:       Vec3,
	diffuse:       Vec3,
	specular:      Vec3,
	direction:     Vec3,
	cut_off:       f32,
	outer_cut_off: f32,
	intensity:     f32,
}


spotLight := SpotLight {
	position      = {-0.2, -0, 10},
	ambient       = {0.2, 0.2, 0.2},
	diffuse       = {0.8, 0.8, 0.8},
	specular      = {1, 1, 1},
	direction     = {0, 0, -1},
	cut_off       = 12.5,
	outer_cut_off = 17.5,
	intensity     = 1,
}
camera := Camera {
	position = Vec3{0, 0, 6},
	target   = Vec3{0, 0, -1},
	up       = Vec3{0, 1, 0},
	yaw      = -90,
	pitch    = 0,
	roll     = 0,
}


MOUSE_SENSITIVITY :: 0.05
mouse_info: struct {
	last_x, last_y: f64,
	zoom:           f64,
	first:          bool,
} = {WIDTH / 2, HEIGHT / 2, 45, true}

mix_val: f32
rot_val: f32
fovy: f32 = FOV
delta_time: f32
last_frame: f32

Data::[8]f32
State:struct{
	Loaded_Textures: [dynamic]Texture
}

init_loaded_textures :: proc(){
	State.Loaded_Textures = make([dynamic]Texture, 0, MIN_NUM_TEXTURES)
}




load_cubemap_dir:: proc(dir_name: string)-> TexID{
	side_names := [6]cstring{"right.jpg", "left.jpg", "top.jpg", "bottom.jpg", "front.jpg", "back.jpg"}
	for name, i in side_names{
		side_names[i] = fmt.ctprintf("%v%v/%v", ASSETS_PATH, dir_name, name)
	}

	return load_cubemap(..side_names[:])
}

get_format_from_n_chan:: proc(n: i32)->(format:i32){
	switch n{
		case 1:
			format = gl.RED
		case 3:
			format = gl.RGB
		case 4:
			format = gl.RGBA
		case:
			format = -1
	}
	
	return
}


load_cubemap:: proc(faces: ..cstring)-> (id: TexID){
	gl.GenTextures(1, &id)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, id)

	width, height, n_chan: i32
	for i in 0..<len(faces){
		data := stbi.load(faces[i], &width, &height, &n_chan, 0)
		if (data!=nil){
			format := get_format_from_n_chan(n_chan)
			gl.TexImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(i), 0, format, width, height, 0, u32(format), gl.UNSIGNED_BYTE, data)
			stbi.image_free(data)
		} else {
			fmt.printfln("Cubemap failed to load at path: %s", faces[i])
			stbi.image_free(data)
		}
	}

	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)

	return
}


init_model :: proc(model: ^Model, relative_path: string) {
	model.relative_path = relative_path
	model.meshes = make([dynamic]Mesh, 0, MIN_NUM_MESHES)

}

@(private)
aiString_to_string :: proc(aiStr: ^ai.aiString) -> string {
	return strings.string_from_ptr(&aiStr.data[0], int(aiStr.length))
}


set_V3 :: proc(program: u32, loc: cstring, val: Vec3) {
	gl.Uniform3f(gl.GetUniformLocation(program, loc), val.x, val.y, val.z)
}

set_V4 :: proc(program: u32, loc: cstring, val: Vec4) {
	gl.Uniform4f(gl.GetUniformLocation(program, loc), val.x, val.y, val.z, val.y)
}

set_mat4:: proc(program:u32, loc: cstring, val: ^matrix[4, 4]f32){
	gl.UniformMatrix4fv(gl.GetUniformLocation(program, loc), 1, gl.FALSE, &val[0, 0] )
}

set_vec3:: proc(program:u32, loc: cstring, val: [3]f32){
	slot := gl.GetUniformLocation(program, loc)
	gl.Uniform3f(slot, val.x, val.y, val.z)
}









process_input :: proc(window: glfw.WindowHandle) {
	if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}

	if glfw.GetKey(window, glfw.KEY_UP) == glfw.PRESS  {
		if !Game.keys_down[glfw.KEY_UP]{
			fmt.println("JAMON")
			Game.player.direction = {0, -1}
			Game.keys_down[glfw.KEY_UP] = true
		}
	} else {
		Game.keys_down[glfw.KEY_UP] = false
	}

	if glfw.GetKey(window, glfw.KEY_DOWN) == glfw.PRESS  {
		if !Game.keys_down[glfw.KEY_DOWN]{
			Game.player.direction = {0, 1}
			Game.keys_down[glfw.KEY_DOWN] = true
		}
	} else {
		Game.keys_down[glfw.KEY_DOWN] = false
	}

	if glfw.GetKey(window, glfw.KEY_LEFT) == glfw.PRESS  {
		if !Game.keys_down[glfw.KEY_LEFT]{
			Game.player.direction = {-1, 0}
			Game.keys_down[glfw.KEY_LEFT] = true
		}
	} else {
		Game.keys_down[glfw.KEY_LEFT] = false
	}

	if glfw.GetKey(window, glfw.KEY_RIGHT) == glfw.PRESS  {
		if !Game.keys_down[glfw.KEY_RIGHT]{
			Game.player.direction = {1, 0}
			Game.keys_down[glfw.KEY_RIGHT] = true
		}
	} else {
		Game.keys_down[glfw.KEY_RIGHT] = false
	}
}



draw_model :: proc(model: ^Model, program: u32) {
	for &mesh in model.meshes {
		draw_mesh(&mesh, program)
	}
}

draw_mesh :: proc(mesh: ^Mesh, program: u32) {
	diffuse_count: u32 = 1
	specular_count: u32 = 1

	for i in 0 ..< len(mesh.textures) {
		gl.ActiveTexture(u32(gl.TEXTURE0 + i))

		name: cstring
		switch mesh.textures[i].type {
		case .DIFFUSE:
			name = fmt.caprintf("material.texture_diffuse%i", diffuse_count)
			diffuse_count += 1
		case .SPECULAR:
			name = fmt.caprintf("material.texture_specular%i", specular_count)
			specular_count += 1
		}
		gl.Uniform1i(gl.GetUniformLocation(program, name), i32(i))
		gl.BindTexture(gl.TEXTURE_2D, mesh.textures[i].id)
	}

	gl.ActiveTexture(gl.TEXTURE0)

	gl.BindVertexArray(mesh.vao)

	gl.DrawElements(gl.TRIANGLES, i32(len(mesh.indices)), gl.UNSIGNED_INT, nil)
	gl.BindVertexArray(0)
}

setup_mesh :: proc(mesh: ^Mesh) {
	vbo: VBO
	vao: VAO
	ebo: EBO

	gl.GenVertexArrays(1, &vao)
	mesh.vao = vao
	gl.GenBuffers(1, &vbo)
	mesh.vbo = vbo
	gl.GenBuffers(1, &ebo)
	mesh.ebo = ebo

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(mesh.vertices) * size_of(Vertex),
		&mesh.vertices[0],
		gl.STATIC_DRAW,
	)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		len(mesh.indices) * size_of(u32),
		&mesh.indices[0],
		gl.STATIC_DRAW,
	)

	gl.VertexAttribPointer(
		index = 0,
		size = 3,
		type = gl.FLOAT,
		normalized = gl.FALSE,
		stride = size_of(Vertex),
		pointer = 0,
	)
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(
		index = 1,
		size = 3,
		type = gl.FLOAT,
		normalized = gl.FALSE,
		stride = size_of(Vertex),
		pointer = offset_of(Vertex, normal),
	)
	gl.EnableVertexAttribArray(1)

	gl.VertexAttribPointer(
		index = 2,
		size = 2,
		type = gl.FLOAT,
		normalized = gl.FALSE,
		stride = size_of(Vertex),
		pointer = offset_of(Vertex, tex_coord),
	)
	gl.EnableVertexAttribArray(2)

	gl.BindVertexArray(0)
}

init_glfw :: proc() {
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

	// We register callbacks
	glfw.SetFramebufferSizeCallback(Window.handler, framebuffer_size_callback)
	glfw.SetCursorPosCallback(Window.handler, mouse_callback)
	glfw.SetScrollCallback(Window.handler, scroll_callback)

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
	gl.Viewport(0, 0, WIDTH, HEIGHT)

}

end_glfw :: proc() {
	glfw.DestroyWindow(Window.handler)
	glfw.Terminate()
}

get_offset :: proc(rows, columns: i32)-> (i32, i32){
	offset_x := Window.w/2 - (columns/2)*CELL_SIZE
	offset_y := Window.h/2 - (rows/2)*CELL_SIZE
	return offset_x, offset_y
}



MAX_NUM_CELLS_PER_GRID :: 6 * 20 * 20
MAX_NUM_INDEXES :: 100
set_grid :: proc(rows: i32, columns: i32, offset_x: i32=0, offset_y: i32=0)->VAO{
	VecData:: struct{
		vertex: Vec3,
		uv: Vec2
	}
	points : [MAX_NUM_CELLS_PER_GRID]VecData
	n: int

	GRID_WIDTH := columns * CELL_SIZE + offset_x
	GRID_HEIGHT := rows * CELL_SIZE + offset_y



	for i := offset_x; i < GRID_WIDTH; i += CELL_SIZE {
		for j := offset_y; j < GRID_HEIGHT; j += CELL_SIZE {
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

	gl.VertexAttribPointer(
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


assign_geometry_shader:: proc(program: u32, gs_name: string){
	gs := gl.CreateShader(gl.GEOMETRY_SHADER)
	gs_source, err:= os.read_entire_file_or_err(gs_name)
	if (err != nil){
		fmt.printfln("Error loading geometry shader. %v", err)
		os.exit(1)
	}
	
	cgs : cstring = strings.clone_to_cstring(transmute(string)gs_source)
	gl.ShaderSource(gs, 1, &cgs, nil)
	gl.CompileShader(gs)
	gl.AttachShader(program, gs)
	gl.LinkProgram(program)
}

load_shaders :: proc(vertex_path, fragment_path:string,  geometry_path: string = "") -> u32 {
    program := gl.CreateProgram()

    vs := gl.CreateShader(gl.VERTEX_SHADER)
    vs_src, _ := os.read_entire_file_or_err(vertex_path)
    cvs: cstring = strings.clone_to_cstring(transmute(string)vs_src)
    gl.ShaderSource(vs, 1, &cvs, nil)
    gl.CompileShader(vs)

    success: i32
    gl.GetShaderiv(vs, gl.COMPILE_STATUS, &success)
    if success == 0 {
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
    if success == 0 {
        buf: [512]u8
        gl.GetShaderInfoLog(fs, 512, nil, &buf[0])
        fmt.printfln("Fragment shader compile error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    gs: u32 = 0
    if geometry_path != "" {
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
    if success == 0 {
        buf: [512]u8
        gl.GetProgramInfoLog(program, 512, nil, &buf[0])
        fmt.printfln("Shader program link error:\n%v", transmute(string)buf[:])
        os.exit(1)
    }

    // Cleanup
    gl.DeleteShader(vs)
    gl.DeleteShader(fs)
    if geometry_path != "" {
        gl.DeleteShader(gs)
    }

    return program
}




load_texture :: proc(name: string, key: E_TEXTURE){
	id: u32
	gl.GenTextures(1, &id)
	
	width, height, n_components: i32

	c_path := strings.clone_to_cstring(name, context.temp_allocator)

	data  := stbi.load(c_path, &width, &height, &n_components, 0)
	if (data!=nil) {
		format : u32
		switch n_components{
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


load_textures :: proc(n:u32, textures: ..string)->[]TexID{
	ids := make([]TexID, len(textures))

	for name, idx in textures {

		image_format: u32
		file_extension := filepath.ext(name)
		switch file_extension {
		case ".png":
			image_format = gl.RGBA
		case ".jpg", ".jpeg":
			image_format = gl.RGB
		case:
			fmt.println("file_extension:", file_extension)
			os.exit(1)
		}

		gl.GenTextures(1, &ids[idx])

		gl.ActiveTexture(u32(gl.TEXTURE0 + idx))
		gl.BindTexture(gl.TEXTURE_2D, ids[idx])

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)



	}
	return ids[:]
}


load_image :: proc(file_path: string, source_format: u32) -> (width, height, n_channels: i32) {
	stbi.set_flip_vertically_on_load(1)

	texture_data := stbi.load(
		strings.clone_to_cstring(file_path, context.temp_allocator),
		&width,
		&height,
		&n_channels,
		0,
	)

	if (texture_data != nil) {
		gl.TexImage2D(
			gl.TEXTURE_2D,
			0,
			gl.RGB,
			width,
			height,
			0,
			source_format,
			gl.UNSIGNED_BYTE,
			texture_data,
		)
		gl.GenerateMipmap(gl.TEXTURE_2D)
		stbi.image_free(texture_data)
	} else {
		fmt.printfln("Error loading texture data from '%v'.", file_path)
		os.exit(1)
	}

	return
}


load_success :: proc(shader: u32) {
	success: [^]i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, success)
	if success[0] != 0 {

		log: [^]u8
		gl.GetShaderInfoLog(shader, 512, nil, log)
		fmt.println("ERROR::SHADER::VERTEX::COMPILATION_FAILED")
		fmt.printfln("%s", log)
	}

}

update :: proc(mat: ^matrix[4, 4]f32) {
	// rot := linalg.matrix4_rotate_f32(rot_val, Vec3{0, 0, 1})
	// mat^ = mat^ * rot
	time := glfw.GetTime()

	mat[0, 1] *= (f32(math.sin(time)) / 2)
	fmt.println(mat[0, 1])
}

import "base:runtime"

mouse_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	using math
	if (mouse_info.first) {

		mouse_info.last_x = xpos
		mouse_info.last_y = ypos
		mouse_info.first = false
	}

	offset_x := xpos - mouse_info.last_x
	offset_y := mouse_info.last_y - ypos // Reversed: y ranges from bottom to top

	mouse_info.last_x = xpos
	mouse_info.last_y = ypos

	offset_x *= MOUSE_SENSITIVITY
	offset_y *= MOUSE_SENSITIVITY

	camera.yaw += f32(offset_x)
	camera.pitch += f32(offset_y)

	if camera.pitch >= 89 {
		camera.pitch = 89
	} else if camera.pitch <= -89 {
		camera.pitch = -89
	}


	dir: Vec3

	dir.x = cos(linalg.RAD_PER_DEG * camera.yaw) * cos(linalg.RAD_PER_DEG * camera.pitch)
	dir.y = sin(linalg.RAD_PER_DEG * camera.pitch)
	dir.z = sin(linalg.RAD_PER_DEG * camera.yaw) * cos(linalg.RAD_PER_DEG * camera.pitch)
	camera.target = linalg.normalize(dir)
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	mouse_info.zoom -= yoffset
	if mouse_info.zoom < 1 {
		mouse_info.zoom = 1
	} else if mouse_info.zoom > 45 {
		mouse_info.zoom = 45
	}
}

// Callback function on window resize.
framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	gl.Viewport(0, 0, width, height)
}


get_cube_positions :: proc() -> []Vec3 {
	arr := [?]Vec3 {
		{0, 0, 0},
		{2, 5, -15},
		{-1.5, -2.2, -2.5},
		{-3.8, -3, -12.3},
		{2.4, -0.4, -3.5},
		{-1.7, 3, -7.5},
		{1.3, -2, -2.5},
		{1.5, 2, -2.5},
		{1.5, 0.2, -1.5},
		{-1.3, 1, -1.5},
	}

	return slice.clone_to_dynamic(arr[:])[:]
}

update_material :: proc() {
	new_color: Vec3
	new_color.x = f32(math.sin(glfw.GetTime() * 2))
	new_color.y = f32(math.sin(glfw.GetTime() * 0.5))
	new_color.z = f32(math.sin(glfw.GetTime() * 1.4))

	mat.diffuse = new_color * 0.5
	mat.ambient = new_color * 0.2

}


out :: proc(line:any=0, loc := #caller_location) {
	fmt.println(line)
	fmt.printf("We are going out on line: %v", loc)
	os.exit(1)
}


get_vertex_data :: proc() -> []f32 {
	data := [?]f32 {
		-0.5,
		-0.5,
		-0.5,
		0.0,
		0.0,
		-1.0,
		0.0,
		0.0,
		0.5,
		-0.5,
		-0.5,
		0.0,
		0.0,
		-1.0,
		1.0,
		0.0,
		0.5,
		0.5,
		-0.5,
		0.0,
		0.0,
		-1.0,
		1.0,
		1.0,
		0.5,
		0.5,
		-0.5,
		0.0,
		0.0,
		-1.0,
		1.0,
		1.0,
		-0.5,
		0.5,
		-0.5,
		0.0,
		0.0,
		-1.0,
		0.0,
		1.0,
		-0.5,
		-0.5,
		-0.5,
		0.0,
		0.0,
		-1.0,
		0.0,
		0.0,
		-0.5,
		-0.5,
		0.5,
		0.0,
		0.0,
		1.0,
		0.0,
		0.0,
		0.5,
		-0.5,
		0.5,
		0.0,
		0.0,
		1.0,
		1.0,
		0.0,
		0.5,
		0.5,
		0.5,
		0.0,
		0.0,
		1.0,
		1.0,
		1.0,
		0.5,
		0.5,
		0.5,
		0.0,
		0.0,
		1.0,
		1.0,
		1.0,
		-0.5,
		0.5,
		0.5,
		0.0,
		0.0,
		1.0,
		0.0,
		1.0,
		-0.5,
		-0.5,
		0.5,
		0.0,
		0.0,
		1.0,
		0.0,
		0.0,
		-0.5,
		0.5,
		0.5,
		-1.0,
		0.0,
		0.0,
		1.0,
		0.0,
		-0.5,
		0.5,
		-0.5,
		-1.0,
		0.0,
		0.0,
		1.0,
		1.0,
		-0.5,
		-0.5,
		-0.5,
		-1.0,
		0.0,
		0.0,
		0.0,
		1.0,
		-0.5,
		-0.5,
		-0.5,
		-1.0,
		0.0,
		0.0,
		0.0,
		1.0,
		-0.5,
		-0.5,
		0.5,
		-1.0,
		0.0,
		0.0,
		0.0,
		0.0,
		-0.5,
		0.5,
		0.5,
		-1.0,
		0.0,
		0.0,
		1.0,
		0.0,
		0.5,
		0.5,
		0.5,
		1.0,
		0.0,
		0.0,
		1.0,
		0.0,
		0.5,
		0.5,
		-0.5,
		1.0,
		0.0,
		0.0,
		1.0,
		1.0,
		0.5,
		-0.5,
		-0.5,
		1.0,
		0.0,
		0.0,
		0.0,
		1.0,
		0.5,
		-0.5,
		-0.5,
		1.0,
		0.0,
		0.0,
		0.0,
		1.0,
		0.5,
		-0.5,
		0.5,
		1.0,
		0.0,
		0.0,
		0.0,
		0.0,
		0.5,
		0.5,
		0.5,
		1.0,
		0.0,
		0.0,
		1.0,
		0.0,
		-0.5,
		-0.5,
		-0.5,
		0.0,
		-1.0,
		0.0,
		0.0,
		1.0,
		0.5,
		-0.5,
		-0.5,
		0.0,
		-1.0,
		0.0,
		1.0,
		1.0,
		0.5,
		-0.5,
		0.5,
		0.0,
		-1.0,
		0.0,
		1.0,
		0.0,
		0.5,
		-0.5,
		0.5,
		0.0,
		-1.0,
		0.0,
		1.0,
		0.0,
		-0.5,
		-0.5,
		0.5,
		0.0,
		-1.0,
		0.0,
		0.0,
		0.0,
		-0.5,
		-0.5,
		-0.5,
		0.0,
		-1.0,
		0.0,
		0.0,
		1.0,
		-0.5,
		0.5,
		-0.5,
		0.0,
		1.0,
		0.0,
		0.0,
		1.0,
		0.5,
		0.5,
		-0.5,
		0.0,
		1.0,
		0.0,
		1.0,
		1.0,
		0.5,
		0.5,
		0.5,
		0.0,
		1.0,
		0.0,
		1.0,
		0.0,
		0.5,
		0.5,
		0.5,
		0.0,
		1.0,
		0.0,
		1.0,
		0.0,
		-0.5,
		0.5,
		0.5,
		0.0,
		1.0,
		0.0,
		0.0,
		0.0,
		-0.5,
		0.5,
		-0.5,
		0.0,
		1.0,
		0.0,
		0.0,
		1.0,
	}

	arr := slice.clone_to_dynamic(data[:])
	return arr[:]
}


get_skybox_data:: proc()->[]f32{
	cube := []f32 {
        -1.0,  1.0, -1.0,
        -1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
        -1.0, -1.0,  1.0,

         1.0, -1.0, -1.0,
         1.0, -1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0, -1.0,
         1.0, -1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0, -1.0,  1.0,
        -1.0, -1.0,  1.0,

        -1.0,  1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0
    }


	return slice.clone_to_dynamic(cube)[:]
}

get_cube_data:: proc()->[]f32{
	
	cube := []f32{
		// back face
		-0.5, -0.5, -0.5,  0.0, 0.0,  0.0,  0.0, -1.0, // bottom-left
		 0.5, -0.5, -0.5,  1.0, 0.0,  0.0,  0.0, -1.0, // bottom-right    
		 0.5,  0.5, -0.5,  1.0, 1.0,  0.0,  0.0, -1.0, // top-right              
		 0.5,  0.5, -0.5,  1.0, 1.0,  0.0,  0.0, -1.0, // top-right
		-0.5,  0.5, -0.5,  0.0, 1.0,  0.0,  0.0, -1.0, // top-left
		-0.5, -0.5, -0.5,  0.0, 0.0,  0.0,  0.0, -1.0, // bottom-left                

		// front face
		-0.5, -0.5,  0.5,  0.0, 0.0,  0.0,  0.0,  1.0, // bottom-left
		 0.5,  0.5,  0.5,  1.0, 1.0,  0.0,  0.0,  1.0, // top-right
		 0.5, -0.5,  0.5,  1.0, 0.0,  0.0,  0.0,  1.0, // bottom-right        
		 0.5,  0.5,  0.5,  1.0, 1.0,  0.0,  0.0,  1.0, // top-right
		-0.5, -0.5,  0.5,  0.0, 0.0,  0.0,  0.0,  1.0, // bottom-left
		-0.5,  0.5,  0.5,  0.0, 1.0,  0.0,  0.0,  1.0, // top-left        

		// left face
		-0.5,  0.5,  0.5,  1.0, 0.0, -1.0,  0.0,  0.0, // top-right
		-0.5, -0.5, -0.5,  0.0, 1.0, -1.0,  0.0,  0.0, // bottom-left
		-0.5,  0.5, -0.5,  1.0, 1.0, -1.0,  0.0,  0.0, // top-left       
		-0.5, -0.5, -0.5,  0.0, 1.0, -1.0,  0.0,  0.0, // bottom-left
		-0.5,  0.5,  0.5,  1.0, 0.0, -1.0,  0.0,  0.0, // top-right
		-0.5, -0.5,  0.5,  0.0, 0.0, -1.0,  0.0,  0.0, // bottom-right

		// right face
		 0.5,  0.5,  0.5,  1.0, 0.0,  1.0,  0.0,  0.0, // top-left
		 0.5,  0.5, -0.5,  1.0, 1.0,  1.0,  0.0,  0.0, // top-right      
		 0.5, -0.5, -0.5,  0.0, 1.0,  1.0,  0.0,  0.0, // bottom-right          
		 0.5, -0.5, -0.5,  0.0, 1.0,  1.0,  0.0,  0.0, // bottom-right
		 0.5, -0.5,  0.5,  0.0, 0.0,  1.0,  0.0,  0.0, // bottom-left
		 0.5,  0.5,  0.5,  1.0, 0.0,  1.0,  0.0,  0.0, // top-left

		// bottom face         
		-0.5, -0.5, -0.5,  0.0, 1.0,  0.0, -1.0,  0.0, // top-right
		 0.5, -0.5,  0.5,  1.0, 0.0,  0.0, -1.0,  0.0, // bottom-left
		 0.5, -0.5, -0.5,  1.0, 1.0,  0.0, -1.0,  0.0, // top-left        
		 0.5, -0.5,  0.5,  1.0, 0.0,  0.0, -1.0,  0.0, // bottom-left
		-0.5, -0.5, -0.5,  0.0, 1.0,  0.0, -1.0,  0.0, // top-right
		-0.5, -0.5,  0.5,  0.0, 0.0,  0.0, -1.0,  0.0, // bottom-right

		// top face
		-0.5,  0.5, -0.5,  0.0, 1.0,  0.0,  1.0,  0.0, // top-left
		 0.5,  0.5, -0.5,  1.0, 1.0,  0.0,  1.0,  0.0, // top-right
		 0.5,  0.5,  0.5,  1.0, 0.0,  0.0,  1.0,  0.0, // bottom-right                 
		 0.5,  0.5,  0.5,  1.0, 0.0,  0.0,  1.0,  0.0, // bottom-right
		-0.5,  0.5,  0.5,  0.0, 0.0,  0.0,  1.0,  0.0, // bottom-left  
		-0.5,  0.5, -0.5,  0.0, 1.0,  0.0,  1.0,  0.0, // top-left              
	}
	return slice.clone_to_dynamic(cube[:])[:]
}

CollisionSystem :: proc(dt: f32){
	player := &Game.player
	new_position := player.position + player.direction 
	if !is_out(new_position, len(Game.board), len(Game.board[0])){
		collide: bool= false
		cell:= get_cell(new_position)
		switch cell.entity.class{
			case .STATIC_COLLIDER:
				collide = true
			case .PLAYER:
			case .EMPTY:
		}
		if !collide do move_player(new_position)
	}

}

get_cell :: proc(pos: Vec2)->Cell{
	return Game.board[int(pos.x)][int(pos.y)]
}


is_out :: proc(pos: Vec2, rows, cols: i32)->bool{
	if pos.y < 0 || pos.y >= f32(cols) do return true
	if pos.x < 0 || pos.x >= f32(rows) do return true
	return false
}

set_player :: proc(pos: Vec2){

	Game.player.position = pos
	Game.board[int(pos.x)][int(pos.y)].entity.texture = textures[.DIRTY_PIG]
	Game.board[int(pos.x)][int(pos.y)].entity.class = .PLAYER
}



move_player :: proc(new_pos: Vec2){
	pos := Game.player.position
	Game.board[int(pos.x)][int(pos.y)].entity.class = .EMPTY

	Game.player.position = new_pos
	Game.board[int(new_pos.x)][int(new_pos.y)].entity.texture = textures[.DIRTY_PIG]
	Game.board[int(new_pos.x)][int(new_pos.y)].entity.class = .PLAYER
}

set_board :: proc(){
	for i in 0..<ROWS{
		for j in 0..<COLUMNS{
			cell := &Game.board[i][j]
			if j == 1 && (i > 1 && i < 8){
				cell.bg_texture = textures[.TM]
				cell.entity.class = .STATIC_COLLIDER
				continue
			}

			if j == 8 && (i > 1 && i < 8){ 
				cell.bg_texture = textures[.BM]
				cell.entity.class = .STATIC_COLLIDER
				continue
			}

			if i == 1 && (j > 1 && j < 8){
				cell.bg_texture = textures[.ML]
				cell.entity.class = .STATIC_COLLIDER
				continue
			}

			if i == 8 && (j > 1 && j < 8){
				cell.bg_texture = textures[.MR]
				cell.entity.class = .STATIC_COLLIDER
				continue
			}

			if i < 8 && i > 1 && j < 8 && j > 1{
				cell.bg_texture = textures[.MM]
				cell.entity.class = .EMPTY
				continue
			} else {
				cell.bg_texture = textures[.DIRTY_PIG]
			}
		}
	}

	Game.board[1][1].bg_texture = textures[.TL]
	Game.board[1][1].entity.class = .STATIC_COLLIDER
	Game.board[1][8].bg_texture = textures[.BL]
	Game.board[1][8].entity.class = .STATIC_COLLIDER
	Game.board[8][1].bg_texture = textures[.TR]
	Game.board[8][1].entity.class = .STATIC_COLLIDER
	Game.board[8][8].bg_texture = textures[.BR]
	Game.board[8][8].entity.class = .STATIC_COLLIDER

}


