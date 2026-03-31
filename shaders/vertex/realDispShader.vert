#version 300 es
precision highp float;

in vec2 vertPosition;
in vec2 vertTexCoord;

uniform vec2 texelSize;

uniform vec2 aspectRatios; // sim   canvas
uniform vec3 view;         // Xpos  Ypos    Zoom
uniform vec3 view3D;       // enabled, perspective strength, height offset

out vec2 texCoord;         // normalized
out vec2 fragCoord;        // non normalized fragment coordinate

out vec2 texCoordXmY0;     // left
out vec2 texCoordXpY0;     // right
out vec2 texCoordX0Yp;     // up
out vec2 texCoordX0Ym;     // down

out vec2 onScreenUV;       // Normalized onscreen coordinates where canvas heigth = 1.0 and width is scaled acording to aspect ratio

uniform float Xmult;       // gl.uniform1f(gl.getUniformLocation(skyBackgroundDisplayProgram, 'Xmult'), horizontalDisplayMult);

const float Ymult = 5.;    // 5.0

void main()
{
  vec2 texCoordAdjusted = vertTexCoord;
  texCoordAdjusted.x *= Xmult;
  texCoordAdjusted.y *= Ymult;

  texCoordAdjusted.x -= (Xmult - 1.0) / (2. * texelSize.x); // make sure the position of texture coordinates stays constant on the screen
  texCoordAdjusted.y -= (Ymult - 1.0) / (2. * texelSize.y);

  // wrapped arround edge
  fragCoord = texCoordAdjusted;
  texCoord = texCoordAdjusted * texelSize; // normalize

  // single area, no wrapping
  // fragCoord = vertTexCoord;
  // texCoord = vertTexCoord * texelSize; // normalize

  texCoordXmY0 = texCoord + vec2(-texelSize.x, 0.0);
  texCoordXpY0 = texCoord + vec2(texelSize.x, 0.0);
  texCoordX0Yp = texCoord + vec2(0.0, texelSize.y);
  texCoordX0Ym = texCoord + vec2(0.0, -texelSize.y);

  vec2 outpos = vertPosition;

  outpos.x *= Xmult;
  outpos.y *= Ymult;

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

  onScreenUV = vec2(outpos.x * aspectRatios[1], outpos.y) * 0.5;

  gl_Position = vec4(outpos, 0.0, 1.0);
}
