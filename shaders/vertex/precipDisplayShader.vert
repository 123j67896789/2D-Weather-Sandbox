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
uniform float stormDepth;
uniform float threeDEnabled;
uniform vec3 threeDRotationDeg; // yaw, pitch, roll
uniform float threeDOrthoScale;
uniform float threeDDepthOffset;
uniform vec3 view3D;       // enabled, perspective strength, height offset

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
  float c = cos(a);
  float s = sin(a);
  return mat3(c, -s, 0.0,
              s, c, 0.0,
              0.0, 0.0, 1.0);
}

void main()
{
  vec3 pos = dropPosition;

  pos.x += view.x;
  pos.y += view.y * aspectRatios[0];
  pos.z += threeDDepthOffset * max(stormDepth, 0.0001);

  if (threeDEnabled > 0.5) {
    vec3 radiansRot = radians(threeDRotationDeg);
    mat3 r = rotY(radiansRot.x) * rotX(radiansRot.y) * rotZ(radiansRot.z);
    pos = r * pos;
  }

  vec2 outpos = pos.xy;

  if (view3D.x > 0.5) {
    float depth = clamp((pos.z / max(stormDepth, 0.0001)) * 0.5 + 0.5, 0.0, 1.0);
    float perspectiveMult = 1.0 - depth * view3D.y;
    outpos.x *= perspectiveMult;
    outpos.y -= depth * view3D.z;
  }

  outpos *= view.z * threeDOrthoScale; // orthographic projection with optional depth offset
  outpos.y *= aspectRatios[1] / aspectRatios[0];

  gl_Position = vec4(outpos, 0.0, 1.0);

  float size = 4.0;
  gl_PointSize = view.z * size / aspectRatios[0];

  position_out = dropPosition;
  mass_out = mass;
  density_out = density;
}
