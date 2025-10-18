#version 330 core

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aTexCoord;

out vec2 texCoord;
uniform mat4 ortho;
uniform vec2 u_flip;

void main(){
  gl_Position = ortho * vec4(aPos, 1.0);

  texCoord = aTexCoord * u_flip + (1.0 - u_flip) * 0.5;
}
