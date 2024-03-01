#version 450

in vec2 _texCoords;

uniform sampler2D tex;

out vec4 color;

void main() {
    color = texture(tex, _texCoords);
}
