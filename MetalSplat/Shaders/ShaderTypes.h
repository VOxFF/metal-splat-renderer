//
//  ShaderTypes.h
//  LearningMetal
//
//  Created by Volodymyr Dubovyi on 6/5/25.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

// Buffer binding slots — must match setVertexBuffer/setFragmentBuffer index arguments on CPU
typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshPositions = 0,  // mesh vertex positions
    BufferIndexMeshGenerics  = 1,  // mesh UVs / other per-vertex data
    BufferIndexUniforms      = 2,  // per-draw uniforms (mesh path)
    BufferIndexSplats        = 3,  // GaussianSplat array (splat path)
    BufferIndexSplatIndices  = 4,  // sorted splat indices (splat path)
    BufferIndexSplatUniforms = 5   // per-draw uniforms (splat path)
};

// Vertex attribute slots — must match MTLVertexDescriptor attribute indices on CPU
typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeTexcoord  = 1,
};

// Texture binding slots — must match setFragmentTexture index arguments on CPU
typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexColor    = 0,
};

// Uniforms for the mesh render path
typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
} Uniforms;

// Per-splat data — 64 bytes, matches GaussianSplatData Swift struct field-for-field
typedef struct
{
    vector_float3 position;  // world-space center
    float         opacity;   // pre-sigmoid [0,1]
    vector_float4 rotation;  // unit quaternion xyzw
    vector_float3 scale;     // half-axes after exp(), world units
    float         _pad0;
    vector_float3 color;     // linear RGB from DC spherical harmonics
    float         _pad1;
} GaussianSplat;

// Uniforms for the splat render path
// viewMatrix is kept separate from modelViewMatrix so the vertex shader
// can reconstruct the Jacobian of the perspective projection at each splat.
typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    vector_float2   viewportSize;  // drawable size in pixels
    vector_float2   _pad;
} SplatUniforms;

#endif /* ShaderTypes_h */

