#!/usr/bin/env node
"use strict";

// Adds Suma's semantic armor-region payload to TEXCOORD_1 (Godot UV2) without
// re-exporting the GLB. Geometry, skinning, materials, images, node names, and
// animations remain byte-for-byte in their existing buffer ranges.

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const REGION_IDS = {
  head: 0,
  neck: 1,
  chest: 2,
  abdomen: 3,
  hips: 4,
  shoulder_l: 5,
  upper_arm_l: 6,
  forearm_l: 7,
  hand_l: 8,
  shoulder_r: 9,
  upper_arm_r: 10,
  forearm_r: 11,
  hand_r: 12,
  thigh_l: 13,
  knee_l: 14,
  shin_l: 15,
  foot_l: 16,
  thigh_r: 17,
  knee_r: 18,
  shin_r: 19,
  foot_r: 20,
  clavicle_l: 21,
  shoulder_cap_l: 22,
  armpit_l: 23,
  upper_chest_l: 24,
  upper_arm_inner_l: 25,
  clavicle_r: 26,
  shoulder_cap_r: 27,
  armpit_r: 28,
  upper_chest_r: 29,
  upper_arm_inner_r: 30,
};

const GLB_MAGIC = 0x46546c67;
const JSON_CHUNK = 0x4e4f534a;
const BIN_CHUNK = 0x004e4942;

function fail(message) {
  throw new Error(message);
}

function parseGlb(buffer) {
  if (buffer.readUInt32LE(0) !== GLB_MAGIC) fail("Not a GLB file");
  if (buffer.readUInt32LE(4) !== 2) fail("Only GLB version 2 is supported");
  const jsonLength = buffer.readUInt32LE(12);
  if (buffer.readUInt32LE(16) !== JSON_CHUNK) fail("Missing JSON chunk");
  const jsonStart = 20;
  const json = JSON.parse(
    buffer
      .subarray(jsonStart, jsonStart + jsonLength)
      .toString("utf8")
      .replace(/[\u0000 ]+$/g, ""),
  );
  const binHeader = jsonStart + jsonLength;
  const binLength = buffer.readUInt32LE(binHeader);
  if (buffer.readUInt32LE(binHeader + 4) !== BIN_CHUNK) {
    fail("Missing BIN chunk");
  }
  return {
    json,
    bin: buffer.subarray(binHeader + 8, binHeader + 8 + binLength),
  };
}

function componentCount(type) {
  return { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 }[type] || 0;
}

function componentSize(componentType) {
  return { 5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4 }[
    componentType
  ];
}

function readComponent(buffer, offset, componentType) {
  switch (componentType) {
    case 5120:
      return buffer.readInt8(offset);
    case 5121:
      return buffer.readUInt8(offset);
    case 5122:
      return buffer.readInt16LE(offset);
    case 5123:
      return buffer.readUInt16LE(offset);
    case 5125:
      return buffer.readUInt32LE(offset);
    case 5126:
      return buffer.readFloatLE(offset);
    default:
      fail(`Unsupported accessor component type ${componentType}`);
  }
}

function readAccessor(gltf, bin, accessorIndex) {
  const accessor = gltf.accessors[accessorIndex];
  if (accessor.sparse) fail("Sparse accessors are not supported");
  const view = gltf.bufferViews[accessor.bufferView];
  const count = componentCount(accessor.type);
  const size = componentSize(accessor.componentType);
  const stride = view.byteStride || count * size;
  const start = (view.byteOffset || 0) + (accessor.byteOffset || 0);
  const result = new Array(accessor.count);
  for (let index = 0; index < accessor.count; index += 1) {
    const values = new Array(count);
    for (let component = 0; component < count; component += 1) {
      values[component] = readComponent(
        bin,
        start + index * stride + component * size,
        accessor.componentType,
      );
    }
    result[index] = values;
  }
  return result;
}

function sideForBone(name) {
  if (name.includes("Left")) return "l";
  if (name.includes("Right")) return "r";
  return "";
}

function sumMatching(weights, pattern) {
  let result = 0;
  for (const [bone, weight] of weights.entries()) {
    if (pattern.test(bone)) result += weight;
  }
  return result;
}

function regionForWeights(weights, centroid) {
  let dominantBone = "";
  let dominantWeight = -1;
  for (const [bone, weight] of weights.entries()) {
    if (weight > dominantWeight) {
      dominantBone = bone;
      dominantWeight = weight;
    }
  }
  const side = sideForBone(dominantBone);
  const left = sumMatching(weights, /Left/);
  const right = sumMatching(weights, /Right/);
  const limbSide = left >= right ? "l" : "r";

  const shoulderWeight = sumMatching(
    weights,
    limbSide === "l" ? /LeftShoulder$/ : /RightShoulder$/,
  );
  if (
    /Shoulder$/.test(dominantBone) ||
    shoulderWeight >= 0.16
  ) {
    const horizontal = Math.abs(centroid[0]);
    if (centroid[1] <= 0.015) return `armpit_${limbSide}`;
    if (horizontal >= 0.205) {
      if (centroid[1] >= 0.14) return `shoulder_cap_${limbSide}`;
      return `upper_arm_inner_${limbSide}`;
    }
    if (centroid[1] >= 0.105) return `clavicle_${limbSide}`;
    return `shoulder_${limbSide}`;
  }
  const neckWeight = sumMatching(weights, /Neck$/);
  if (
    neckWeight >= 0.16 &&
    centroid[1] >= 0.105 &&
    centroid[1] <= 0.215
  ) {
    return "neck";
  }
  if (/Head$/.test(dominantBone)) return "head";
  if (/Neck$/.test(dominantBone)) return "neck";
  if (/Hand|Thumb|Index/.test(dominantBone)) return `hand_${side || limbSide}`;
  if (/ForeArm$/.test(dominantBone)) return `forearm_${side || limbSide}`;
  if (/Arm$/.test(dominantBone)) {
    if (
      Math.abs(centroid[0]) <= 0.285 &&
      centroid[1] >= -0.035
    ) {
      return `upper_arm_inner_${side || limbSide}`;
    }
    return `upper_arm_${side || limbSide}`;
  }

  const upperLegWeight = sumMatching(
    weights,
    limbSide === "l" ? /LeftUpLeg$/ : /RightUpLeg$/,
  );
  const lowerLegWeight = sumMatching(
    weights,
    limbSide === "l" ? /LeftLeg$/ : /RightLeg$/,
  );
  const footWeight = sumMatching(
    weights,
    limbSide === "l"
      ? /Left(?:Foot|ToeBase)$/
      : /Right(?:Foot|ToeBase)$/,
  );
  if (
    upperLegWeight >= 0.14 &&
    lowerLegWeight >= 0.14 &&
    centroid[1] >= -0.355
  ) {
    return `knee_${limbSide}`;
  }
  if (/UpLeg$/.test(dominantBone)) return `thigh_${side || limbSide}`;
  if (
    lowerLegWeight >= 0.10 &&
    centroid[1] > -0.405 &&
    footWeight < 0.72
  ) {
    return `shin_${limbSide}`;
  }
  if (/Leg$/.test(dominantBone)) return `shin_${side || limbSide}`;
  if (/Foot$|ToeBase$/.test(dominantBone)) return `foot_${side || limbSide}`;
  if (/Spine2$/.test(dominantBone)) {
    if (
      Math.abs(centroid[0]) >= 0.075 &&
      centroid[1] >= 0.015
    ) {
      return `upper_chest_${centroid[0] >= 0 ? "l" : "r"}`;
    }
    return "chest";
  }
  if (/Spine1$/.test(dominantBone)) return "abdomen";
  if (/Spine$/.test(dominantBone)) return "abdomen";
  if (/Hips$/.test(dominantBone)) return "hips";
  fail(`No armor region rule for dominant bone '${dominantBone}'`);
}

function classifyTriangles(gltf, bin, primitive) {
  const positions = readAccessor(gltf, bin, primitive.attributes.POSITION);
  const joints = readAccessor(gltf, bin, primitive.attributes.JOINTS_0);
  const weights = readAccessor(gltf, bin, primitive.attributes.WEIGHTS_0);
  if (
    positions.length !== joints.length ||
    joints.length !== weights.length ||
    joints.length % 3 !== 0
  ) {
    fail("Expected an unindexed triangle list with matching skin accessors");
  }
  const skin = gltf.skins[primitive.skin || 0] || gltf.skins[0];
  const jointNames = skin.joints.map((nodeIndex) => gltf.nodes[nodeIndex].name);
  const ids = new Float32Array(joints.length * 2);
  const counts = {};
  const centroidBounds = {};

  for (let triangle = 0; triangle < joints.length / 3; triangle += 1) {
    const combined = new Map();
    const centroid = [0, 0, 0];
    for (let corner = 0; corner < 3; corner += 1) {
      const vertex = triangle * 3 + corner;
      for (let axis = 0; axis < 3; axis += 1) {
        centroid[axis] += positions[vertex][axis] / 3;
      }
      for (let influence = 0; influence < 4; influence += 1) {
        const weight = weights[vertex][influence];
        if (weight <= 0.00001) continue;
        const bone = jointNames[joints[vertex][influence]];
        combined.set(bone, (combined.get(bone) || 0) + weight / 3);
      }
    }
    const region = regionForWeights(combined, centroid);
    const regionId = REGION_IDS[region];
    counts[region] = (counts[region] || 0) + 1;
    if (!centroidBounds[region]) {
      centroidBounds[region] = {
        min: [...centroid],
        max: [...centroid],
      };
    } else {
      for (let axis = 0; axis < 3; axis += 1) {
        centroidBounds[region].min[axis] = Math.min(
          centroidBounds[region].min[axis],
          centroid[axis],
        );
        centroidBounds[region].max[axis] = Math.max(
          centroidBounds[region].max[axis],
          centroid[axis],
        );
      }
    }
    for (let corner = 0; corner < 3; corner += 1) {
      ids[(triangle * 3 + corner) * 2] = regionId;
      ids[(triangle * 3 + corner) * 2 + 1] = 0;
    }
  }
  return { ids, counts, centroidBounds };
}

function pad4(buffer, fill = 0) {
  const paddedLength = (buffer.length + 3) & ~3;
  if (paddedLength === buffer.length) return buffer;
  return Buffer.concat([
    buffer,
    Buffer.alloc(paddedLength - buffer.length, fill),
  ]);
}

function encodeGlb(gltf, oldBin, regionBytes) {
  const alignedBin = pad4(oldBin);
  const regionOffset = alignedBin.length;
  const newBin = pad4(Buffer.concat([alignedBin, regionBytes]));
  gltf.buffers[0].byteLength = newBin.length;

  const viewIndex = gltf.bufferViews.length;
  gltf.bufferViews.push({
    buffer: 0,
    byteOffset: regionOffset,
    byteLength: regionBytes.length,
    byteStride: 8,
    target: 34962,
    name: "PlayerArmorRegionUV2",
  });
  const accessorIndex = gltf.accessors.length;
  gltf.accessors.push({
    bufferView: viewIndex,
    componentType: 5126,
    count: regionBytes.length / 8,
    type: "VEC2",
    min: [0, 0],
    max: [Math.max(...Object.values(REGION_IDS)), 0],
    name: "PlayerArmorRegionUV2",
  });
  gltf.meshes[0].primitives[0].attributes.TEXCOORD_1 = accessorIndex;

  const jsonBytes = pad4(Buffer.from(JSON.stringify(gltf), "utf8"), 0x20);
  const totalLength = 12 + 8 + jsonBytes.length + 8 + newBin.length;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(GLB_MAGIC, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLength, 8);
  const jsonHeader = Buffer.alloc(8);
  jsonHeader.writeUInt32LE(jsonBytes.length, 0);
  jsonHeader.writeUInt32LE(JSON_CHUNK, 4);
  const binHeader = Buffer.alloc(8);
  binHeader.writeUInt32LE(newBin.length, 0);
  binHeader.writeUInt32LE(BIN_CHUNK, 4);
  return Buffer.concat([header, jsonHeader, jsonBytes, binHeader, newBin]);
}

function main() {
  if (process.argv.length < 4) {
    fail("Usage: node bake_player_armor_regions.js input.glb output.glb");
  }
  const inputPath = path.resolve(process.argv[2]);
  const outputPath = path.resolve(process.argv[3]);
  if (!fs.existsSync(inputPath)) fail(`Missing input GLB: ${inputPath}`);

  const source = fs.readFileSync(inputPath);
  const { json: gltf, bin } = parseGlb(source);
  if (gltf.meshes.length !== 1 || gltf.meshes[0].primitives.length !== 1) {
    fail("Expected the current player GLB to contain one mesh primitive");
  }
  const primitive = gltf.meshes[0].primitives[0];
  if (primitive.indices !== undefined) {
    fail("Expected the current player primitive to be an unindexed triangle list");
  }
  if (primitive.attributes.TEXCOORD_1 !== undefined) {
    fail("Input already contains TEXCOORD_1; bake from the clean player GLB");
  }
  if (
    primitive.attributes.JOINTS_0 === undefined ||
    primitive.attributes.WEIGHTS_0 === undefined
  ) {
    fail("Player GLB has no skin weight attributes");
  }

  const { ids, counts, centroidBounds } = classifyTriangles(
    gltf,
    bin,
    primitive,
  );
  gltf.meshes[0].extras = {
    ...(gltf.meshes[0].extras || {}),
    sumaArmorRegions: {
      version: 1,
      ids: REGION_IDS,
      triangleCounts: counts,
      centroidBounds,
    },
  };
  const regionBytes = Buffer.from(
    ids.buffer,
    ids.byteOffset,
    ids.byteLength,
  );
  const result = encodeGlb(gltf, bin, regionBytes);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, result);

  console.log(
    JSON.stringify(
      {
        input: inputPath,
        output: outputPath,
        inputSha256: crypto.createHash("sha256").update(source).digest("hex"),
        outputSha256: crypto.createHash("sha256").update(result).digest("hex"),
        vertices: ids.length / 2,
        triangles: ids.length / 6,
        triangleCounts: counts,
        centroidBounds,
        regionIds: REGION_IDS,
      },
      null,
      2,
    ),
  );
}

main();
