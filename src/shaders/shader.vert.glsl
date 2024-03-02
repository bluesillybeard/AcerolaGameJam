#version 450

in vec3 pos;
in vec2 texCoord;

uniform mat4 transform;

out vec2 _texCoords;

void main() {
    _texCoords = texCoord;
    gl_Position = transform * vec4(pos, 1);
}
