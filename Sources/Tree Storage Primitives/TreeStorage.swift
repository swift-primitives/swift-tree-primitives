// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-primitives open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-primitives project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

// MARK: - TreeStorage — the non-generic namespace for the tree family's storage columns
//
// The Charter at-target reshape ([DS-025]) makes `Tree<S: ~Copyable>` generic over its
// storage column `S`. `TreeStorage` is the NON-GENERIC namespace enum hosting those
// columns ([API-NAME-001] `Nest.Name`): the dynamic column (``Dynamic``, this package)
// and — in their own variant packages ([DS-027]) — the n-ary and keyed columns, each
// conforming the ``__TreeStorage`` capability and usable as the `S` of `Tree<S>`.
//
// It is a TOP-LEVEL type, deliberately NOT nested in `Tree<S>`: a type nested in `Tree<S>`
// would capture the generic parameter `S`, and a namespaced generic typealias over
// `Tree<S>` crashes the 6.3.2 frontend (both probe-confirmed). The standalone namespace
// gives the columns their `Nest.Name` without the capture/crash.

/// The non-generic namespace for the tree family's storage columns.
///
/// Hosts the dynamic column (``Dynamic``, this package) and — in their own packages —
/// the n-ary and keyed columns, each conforming the ``__TreeStorage`` capability and
/// usable as the `S` of `Tree<S>`.
public enum TreeStorage {}
