#version 330 core
out vec4 FragColor;

in vec2 texCoord;

uniform vec4 color;
uniform sampler2D texture1; 

void main(){
    FragColor = texture(texture1, texCoord);

    
    // FragColor = vec4(texCoord, 0, 1);
    // FragColor = vec4(1,0,0,1);
}
