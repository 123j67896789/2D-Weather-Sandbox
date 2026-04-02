#version 300 es
precision highp float;


in vec3 dropPosition;
in vec2 mass; //[0] water   [1] ice
in float density;

// transform feedback varyings:
out vec3 position_out;
out vec2 mass_out;
out float density_out;

// via fragmentshader to feedback framebuffers for feedback to fluid
out vec4 feedback;
out vec2 deposition; // for rain and snow accumulation on surface

vec2 texCoord;
vec4 water;
vec4 base;
float realTemp;

uniform sampler2D baseTex;
uniform sampler2D waterTex;
uniform sampler2D lightningDataTex;

uniform vec2 resolution;
uniform vec2 texelSize;
uniform float dryLapse;

uniform float iterNum;          // used as seed for random function
uniform float numDroplets;      // total number of droplets
uniform float inactiveDroplets; // used to maintain constant spawnrate

uniform float evapHeat;
uniform float meltingHeat;

// prcipitation settings:
uniform float aboveZeroThreshold; // 1.0
uniform float subZeroThreshold;   // 0.0
uniform float spawnChanceMult;    //
uniform float snowDensity;        // 0.2 - 0.5
uniform float fallSpeed;          // 0.0003
uniform float growthRate0C;       // 0.0005
uniform float growthRate_30C;     // 0.01
uniform float freezingRate;       // 0.0002
uniform float meltingRate;        // 0.0015
uniform float evapRate;           // 0.0005
uniform float stormDepth;
uniform float stormTilt;
uniform float supercellShear;
uniform float supercellInflowTwist;
uniform float mesocycloneLift;
uniform float hailCoreBoost;
uniform float spcRiskMult;
uniform float capeJkg;
uniform float srh;
uniform float stp;
uniform float vtp;
uniform float dewPointC;
uniform float helicity;
uniform float simDeltaSeconds;
uniform int dustDevilCount;
uniform vec4 dustDevils[8];     // x, y, radius, strength
uniform vec4 dustDevilState[8]; // height, energy, age01, active

#include "common.glsl"

vec3 newPos;
vec2 newMass;
float newDensity;
bool isDust = false;

bool isActive = true;
bool spawned = false; // spawned in this iteration
bool lightningSpawned = false;

float signedHorizontalDelta(float fromX, float toX)
{
  float dx = toX - fromX;
  if (dx > 0.5)
    dx -= 1.0;
  else if (dx < -0.5)
    dx += 1.0;
  return dx;
}

void disableDroplet()
{
  newMass[WATER] = -2. - dropPosition.x; // disable droplet by making it negative and save position as seed for respawning
  newMass[ICE] = dropPosition.y;         // save position as seed for random function when respawning later
}

void main()
{
  feedback = vec4(0.0);
  deposition = vec2(0.0);

  newPos = dropPosition;
  newMass = mass;         // amount of water and ice carried
  newDensity = density;   // determines fall speed

  if (mass[WATER] < 0.) { // inactive
    for (int devilIndex = 0; devilIndex < 8; devilIndex++) {
      if (devilIndex >= dustDevilCount) {
        break;
      }

      vec4 devil = dustDevils[devilIndex];
      vec4 devilState = dustDevilState[devilIndex];
      if (devilState.w < 0.5 || devilState.y < 0.08) {
        continue;
      }

      float angle = random2d(vec2(mass[WATER] + float(devilIndex) * 0.18, iterNum * 0.051 + dropPosition.x)) * 6.28318;
      float radial = sqrt(random2d(vec2(mass[ICE] + float(devilIndex) * 0.41, iterNum * 0.037 + dropPosition.y))) * devil.z;
      float height = random2d(vec2(dropPosition.x + float(devilIndex) * 0.77, iterNum * 0.023 + mass[ICE])) * devilState.x;
      float aspect = texelSize.x / max(texelSize.y, 0.000001);
      vec2 spawnTc = vec2(devil.x + cos(angle) * radial * aspect, devil.y + height);
      spawnTc.x = mod(spawnTc.x + 1.0, 1.0);
      spawnTc.y = clamp(spawnTc.y, 0.0, 1.0);

      float dustSpawnChance = devilState.y * devil.w * 0.12;
      float dustRand = random2d(vec2(spawnTc.x + iterNum * 0.011, spawnTc.y + float(devilIndex) * 0.17));
      if (dustSpawnChance > dustRand) {
        spawned = true;
        isDust = true;
        newPos = vec3((spawnTc.x - 0.5) * 2., (spawnTc.y - 0.5) * 2., 0.0);
        newMass[WATER] = 0.04 + devilState.y * 0.06;
        newMass[ICE] = 30.0; // lifetime (seconds)
        newDensity = 2.0;    // marker for dust particles
        break;
      }
    }

    if (spawned && isDust) {
      gl_PointSize = 1.0;
      gl_Position = vec4(newPos.xy, 0.0, 1.0);
      position_out = newPos;
      mass_out = newMass;
      density_out = newDensity;
      return;
    }

    texCoord = vec2(random2d(vec2(mass[WATER], dropPosition.x + iterNum * 0.3754)), random2d(vec2(mass[ICE], dropPosition.x + iterNum * 0.073162)));

    // sample fluid at generated position
    base = texture(baseTex, texCoord);
    water = texture(waterTex, texCoord);

    // check if position is okay to spawn
    realTemp = potentialToRealT(base[TEMPERATURE]); // in Kelvin

#define initalMass 0.15                             // 0.05 initial droplet mass
    float threshold;                                // minimal cloudwater before precipitation develops
    if (realTemp > CtoK(0.0))
      threshold = aboveZeroThreshold;               // in above freezing conditions coalescence only happens in really dense clouds
    else
      threshold = subZeroThreshold;

    if (water[CLOUD] > threshold && base[TEMPERATURE] < 500.) {
      float capeMult = clamp(capeJkg / 2500.0, 0.25, 2.5);
      float stpMult = 1.0 + stp * 0.10;
      float moistureMult = clamp(map_range(CtoK(dewPointC), CtoK(-10.0), CtoK(26.0), 0.6, 1.5), 0.4, 1.8);
      float spawnChance = ((water[CLOUD] - threshold) / (inactiveDroplets + 10.0)) * resolution.x * resolution.y * spawnChanceMult * spcRiskMult * capeMult * stpMult * moistureMult;
      float nrmRand = fract(pow(water[CLOUD] * 10.0, 2.0));

      if (spawnChance > nrmRand) {                                       // spawn precipitation particle
        spawned = true;
        newPos = vec3((texCoord.x - 0.5) * 2., (texCoord.y - 0.5) * 2., 0.0); // convert texture coordinate (0 to 1) to position (-1 to 1)

        if (realTemp < CtoK(0.0)) {                                      // below 0 C
          newMass[WATER] = 0.0;                                          // enable
          newMass[ICE] = initalMass;                                     // snow
          feedback[HEAT] += newMass[ICE] * meltingHeat;                  // add heat of freezing
          newDensity = snowDensity;

          vec4 lightningData = texture(lightningDataTex, vec2(0.5)); // data from last lightning bolt

          const float lightningCloudDensityThreshold = 2.5;          // 3.0
          const float lightningChanceMultiplier = 0.0033;            // 0.0011

          float cloudPlusPrecipDensity = water[CLOUD] + water[PRECIPITATION];

          float lightningSpawnChance = max((cloudPlusPrecipDensity - lightningCloudDensityThreshold) * lightningChanceMultiplier, 0.);

          const float minIterationsSinceLastLightningBolt = 30.;

          if (lightningData[START_ITERNUM] < iterNum - minIterationsSinceLastLightningBolt && random2d(vec2(base[TEMPERATURE] * 0.2324, water[TOTAL] * 7.7)) < lightningSpawnChance) {
            lightningSpawned = true;
            isActive = false;
            gl_PointSize = 1.0;
            feedback.xy = texCoord;
            feedback[START_ITERNUM] = iterNum;
            feedback[INTENSITY] = clamp(cloudPlusPrecipDensity / 10.0 + (random2d(texCoord) - 0.5), 0.01, 4.0);
            gl_Position = vec4(vec2(-1. + texelSize.x * 3., -1. + texelSize.y), 0.0, 1.0);
          }
        } else {
          newMass[WATER] = initalMass; // rain
          newMass[ICE] = 0.0;
          newDensity = 1.0;
        }
        feedback[VAPOR] -= initalMass;
      }
    }

    if (spawned) {
      if (!lightningSpawned) {
        gl_PointSize = 1.0;
        gl_Position = vec4(newPos.xy, 0.0, 1.0);
      }
    } else { // still inactive
      isActive = false;
      gl_PointSize = 1.0;
      feedback[MASS] = 1.0;
      gl_Position = vec4(vec2(-1. + texelSize.x, -1. + texelSize.y), 0.0, 1.0);
    }
  }

  if (isActive) {
    if (!spawned) {
      texCoord = vec2(dropPosition.x / 2. + 0.5,
                      dropPosition.y / 2. + 0.5);
      water = texture(waterTex, texCoord);
      base = texture(baseTex, texCoord);
      realTemp = potentialToRealT(base[TEMPERATURE]); // in Kelvin
    }

    if (newDensity > 1.5) { // dust particle path
      vec2 dustTc = vec2(newPos.x / 2. + 0.5, newPos.y / 2. + 0.5);
      vec2 dustVel = vec2(0.0);
      float updraft = 0.0;
      float supportEnergy = 0.0;

      for (int devilIndex = 0; devilIndex < 8; devilIndex++) {
        if (devilIndex >= dustDevilCount) {
          break;
        }

        vec4 devil = dustDevils[devilIndex];
        vec4 devilState = dustDevilState[devilIndex];
        if (devilState.w < 0.5) {
          continue;
        }

        vec2 delta = vec2(signedHorizontalDelta(devil.x, dustTc.x), dustTc.y - devil.y);
        delta.x *= texelSize.y / max(texelSize.x, 0.000001);
        float radialCore = smoothstep(devil.z, 0.0, length(delta));
        float top = devil.y + max(devilState.x, texelSize.y * 4.0);
        float towerShape = smoothstep(devil.y, devil.y + texelSize.y * 0.7, dustTc.y) * (1.0 - smoothstep(top * 0.75, top, dustTc.y));
        float influence = radialCore * towerShape * devilState.y * devil.w;
        if (influence <= 0.0) {
          continue;
        }

        vec2 tangent = normalize(vec2(-delta.y, delta.x) + vec2(1e-6, 0.0));
        dustVel += tangent * influence * 0.010;
        updraft += influence * 0.0035;
        supportEnergy = max(supportEnergy, influence);
      }

      newPos.xy += base.xy / resolution * 2.0;
      newPos.xy += dustVel;
      newPos.y += updraft;
      newPos.x = mod(newPos.x + 1.0, 2.0) - 1.0;

      newMass[ICE] -= simDeltaSeconds;
      newMass[WATER] *= 1.0 - (0.010 + max(0.12 - supportEnergy, 0.0) * 0.04);

      if (newMass[ICE] <= 0.0 || newMass[WATER] < 0.003 || supportEnergy <= 0.001 || newPos.y > 1.0) {
        disableDroplet();
      }

      gl_PointSize = 7.0;
      gl_Position = vec4(newPos.xy, 0.0, 1.0);
      position_out = newPos;
      mass_out = newMass;
      density_out = max(newDensity, 0.);
      return;
    }

    float totalMass = newMass[WATER] + newMass[ICE];

    if (totalMass < 0.04) {
      feedback[HEAT] = -(totalMass * evapHeat);
      feedback[VAPOR] = totalMass;

      disableDroplet();

    } else if (newPos.y < -1.0 || water[TOTAL] > 1000.) {

      if (texture(baseTex, vec2(texCoord.x, texCoord.y + texelSize.y))[TEMPERATURE] > 500.)
        newPos.y += texelSize.y * 1.;

      deposition[RAIN_DEPOSITION] = newMass[WATER];
      deposition[SNOW_DEPOSITION] = newMass[ICE];

      disableDroplet();

    } else {
      float surfaceArea = pow(totalMass, 1. / 3.); // As if droplet is a sphere (3D)

      float growthRate = max(map_range(realTemp, CtoK(0.0), CtoK(-30.0), growthRate0C, growthRate_30C), growthRate0C);

      float growth = water[CLOUD] * growthRate * surfaceArea * (1.0 + vtp * 0.08);

      if (realTemp < CtoK(0.0) && water[CLOUD] > 0.0 && density == 1.0) {
        growth += surfaceArea * water[PRECIPITATION] * (0.0030 + hailCoreBoost * 0.0030);
      }

      feedback[VAPOR] -= growth * 1.0;

      if (realTemp < CtoK(0.0)) {

        newMass[ICE] += growth;
        feedback[HEAT] += growth * meltingHeat;

        float freezing = min((CtoK(0.0) - realTemp) * freezingRate * surfaceArea, newMass[WATER]);
        newMass[WATER] -= freezing;
        newMass[ICE] += freezing;
        feedback[HEAT] += freezing * meltingHeat;

      } else {
        newMass[WATER] += growth;

        float melting = min((realTemp - CtoK(0.0)) * meltingRate * surfaceArea, newMass[ICE]);
        newMass[ICE] -= melting;
        newMass[WATER] += melting;
        feedback[HEAT] -= melting * meltingHeat;

        newDensity = min(newDensity + (melting / totalMass) * 1.00, 1.0);
      }

      float dropletTemp = potentialToRealT(base[TEMPERATURE]);

      if (newMass[ICE] > 0.0)
        dropletTemp = min(dropletTemp, CtoK(0.0));

      float evapAndSubli = max((maxWater(dropletTemp) - water[TOTAL]) * surfaceArea * evapRate, 0.);

      float evap = min(newMass[WATER], evapAndSubli);
      float subli = min(newMass[ICE], evapAndSubli - evap);

      newMass[WATER] -= evap;
      newMass[ICE] -= subli;

      feedback[VAPOR] += evap;
      feedback[VAPOR] += subli;
      feedback[HEAT] -= evap * evapHeat;
      feedback[HEAT] -= subli * evapHeat;
      feedback[HEAT] -= subli * meltingHeat;

      // Update position
      newPos.xy += base.xy / resolution * 2.;

      float srhTerm = clamp(srh / 300.0, 0.0, 3.0);
      float helicityTerm = clamp(helicity / 350.0, 0.0, 3.0);
      float zShear = base.x * supercellShear * (0.3 + srhTerm * 0.15);
      float inflowTwist = supercellInflowTwist * (-newPos.y) * sign(base.x) * (0.25 + helicityTerm * 0.12);
      newPos.z += zShear * texelSize.x + inflowTwist * texelSize.y;

      float capeUpdraft = clamp(capeJkg / 4000.0, 0.0, 1.6);
      float updraftFactor = clamp((base.y * 0.5 + water[CLOUD] * 0.25 + capeUpdraft * 0.4) * mesocycloneLift, -1.0, 2.5);
      newPos.z += updraftFactor * texelSize.y;

      newPos.y -= fallSpeed * newDensity * sqrt(totalMass / surfaceArea);

      newPos.x += newPos.z * stormTilt * texelSize.x * 2.0;
      newPos.z = clamp(newPos.z, -stormDepth, stormDepth);

      newPos.x = mod(newPos.x + 1., 2.) - 1.;

      feedback[MASS] = totalMass;

    }

#define pntSize 12.
    const float pntSurface = pntSize * pntSize;
    feedback[MASS] /= pntSurface;
    feedback[HEAT] /= pntSurface;
    feedback[VAPOR] /= pntSurface;

    deposition[RAIN_DEPOSITION] /= pntSize;
    deposition[SNOW_DEPOSITION] /= pntSize;

    gl_PointSize = pntSize;

    gl_Position = vec4(newPos.xy, 0.0, 1.0);
  }

  position_out = newPos;
  mass_out = newMass;
  density_out = max(newDensity, 0.);
}
