#version 300 es
precision highp float;

in vec3 dropPosition;
in vec2 mass; //[0] water   [1] ice
in float density;

out vec3 position_out;
out vec2 mass_out;
out float density_out;

uniform vec2 texelSize;
uniform vec2 aspectRatios; // sim   canvas
uniform vec3 view;         // Xpos  Ypos    Zoom
uniform vec3 view3D;       // enabled, perspective strength, height offset
uniform float stormDepth;

mat3 rotX(float a)
{
  float c = cos(a);
  float s = sin(a);
  return mat3(1.0, 0.0, 0.0,
              0.0, c, -s,
              0.0, s, c);
}

mat3 rotY(float a)
{
  float c = cos(a);
  float s = sin(a);
  return mat3(c, 0.0, s,
              0.0, 1.0, 0.0,
              -s, 0.0, c);
}

mat3 rotZ(float a)
{
  vec2 outpos = dropPosition.xy;

void main()
{
  vec3 pos = dropPosition;

  pos.x += view.x;
  pos.y += view.y * aspectRatios[0];
  pos.z += threeDDepthOffset * max(stormDepth, 0.0001);

  if (view3D.x > 0.5) {
    float depth = clamp((dropPosition.z / max(stormDepth, 0.0001)) * 0.5 + 0.5, 0.0, 1.0);
    float perspectiveMult = 1.0 - depth * view3D.y;
    outpos.x *= perspectiveMult;
    outpos.y -= depth * view3D.z;
  }

  vec2 outpos = pos.xy;
  outpos *= view.z * threeDOrthoScale; // orthographic projection, no perspective
  outpos.y *= aspectRatios[1] / aspectRatios[0];

  gl_Position = vec4(outpos, 0.0, 1.0);

  float size = 4.0;

  gl_PointSize = view[2] * size / aspectRatios[0];

  position_out = dropPosition;
  mass_out = mass;
  density_out = density;
}
