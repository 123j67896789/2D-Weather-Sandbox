#version 300 es
precision highp float;

in vec2 vertPosition;
in vec2 vertTexCoord;

uniform vec2 texelSize;

uniform vec2 aspectRatios; // sim   canvas
uniform vec3 view;         // Xpos  Ypos    Zoom
uniform vec3 view3D;       // enabled, perspective strength, height offset

uniform float Xmult;

out vec2 texCoord;  // normalized
out vec2 fragCoord; // non normalized fragment coordinate

void main()
{
  vec2 texCoordAdjusted = vertTexCoord;
  texCoordAdjusted.x *= Xmult;

  texCoordAdjusted.x -= (Xmult - 1.0) / (2. * texelSize.x); // make sure the position of texture coordinats stays constant on the screen

  fragCoord = texCoordAdjusted;
  texCoord = texCoordAdjusted * texelSize; // normalize

  vec2 outpos = vertPosition;

  outpos.x *= Xmult;

  outpos.x += view.x;
  outpos.y += view.y * aspectRatios[0];

  outpos *= view[2]; // zoom

  if (view3D.x > 0.5) {
    float depth = clamp(texCoord.y, 0.0, 1.0);
    float perspectiveMult = 1.0 - depth * view3D.y;
    outpos.x *= perspectiveMult;
    outpos.y -= depth * view3D.z;
  }

  outpos.y *= aspectRatios[1] / aspectRatios[0];

  gl_Position = vec4(outpos, 0.0, 1.0);
}
