@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * uy.kohesive.injekt — how extensions reach things the host owns.
 *
 * `Injekt` is a top-level PROPERTY, not an object: Kotlin compiles it to
 * `InjektKt.getInjekt()`, which is exactly the symbol a real extension looked
 * for. Declaring it as an object produces a class instead, and every source
 * fails with NoSuchMethodError at construction.
 *
 * Signatures reproduced for compatibility; behaviour is ours, and no code is
 * copied from the Apache-2.0 original (INSTRUCTIONS.md §13).
 */
package uy.kohesive.injekt

import uy.kohesive.injekt.api.InjektModule
import uy.kohesive.injekt.api.InjektScope

/** Compiles to `InjektKt.getInjekt(): InjektScope`. */
val Injekt: InjektScope = InjektScope()

/** `by injectLazy()` is how a source field usually grabs NetworkHelper. */
inline fun <reified T : Any> injectLazy(): Lazy<T> =
    lazy(LazyThreadSafetyMode.SYNCHRONIZED) { Injekt.getInstance(T::class.java) }

inline fun <reified T : Any> injectValue(): T = Injekt.getInstance(T::class.java)

fun importModule(module: InjektModule) = Injekt.importModule(module)
