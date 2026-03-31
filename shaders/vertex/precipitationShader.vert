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

#include "common.glsl"

vec3 newPos;
vec2 newMass;
float newDensity;

bool isActive = true;
bool spawned = false; // spawned in this iteration
bool lightningSpawned = false;

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
      float spawnChance = ((water[CLOUD] - threshold) / (inactiveDroplets + 10.0)) * resolution.x * resolution.y * spawnChanceMult;
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


      float growth = water[CLOUD] * growthRate * surfaceArea;

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
      float zShear = base.x * supercellShear * 0.5;
      float inflowTwist = supercellInflowTwist * (-newPos.y) * sign(base.x) * 0.5;
      newPos.z += zShear * texelSize.x + inflowTwist * texelSize.y;

      float updraftFactor = clamp((base.y * 0.5 + water[CLOUD] * 0.25) * mesocycloneLift, -1.0, 2.0);
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
