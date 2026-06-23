// DEPRECATED — transitional shim (L1 core-dissolution sweep 2026-06-23). Re-exports the dissolved Core surface; removed in the cleanup wave.
//
// `Tree Primitives Core` was the family home (the `Tree` namespace shell + the
// `__TreeStorage`/`__TreeProtocol` seams + the shared arena + the canonical dynamic
// column). Its content dissolved into the singular root `Tree Primitive` plus the
// `Tree Index Primitives` / `Tree Storage Primitives` / `Tree Operations Primitives`
// sub-namespaces. This target survives ONLY as an exports-only shim so that consumers
// (`tree-keyed`, `tree-n`, `BuildAll`) importing `Tree_Primitives_Core` keep resolving
// the full pre-migration surface until the cleanup wave repoints them. Zero implementation.

@_exported public import Tree_Primitive
@_exported public import Tree_Index_Primitives
@_exported public import Tree_Storage_Primitives
@_exported public import Tree_Operations_Primitives

// The single external module the pre-migration Core funneled via its own exports.swift.
// (The remaining externals — Storage_Generational, Store, Column, Shared, Buffer_Ring,
// Queue, Stack, Property — flow through the sub-namespaces' `public import`s above.)
@_exported public import Index_Primitives
