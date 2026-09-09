@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * uy.kohesive.injekt.api — the types extensions name when they touch Injekt.
 * Signatures only; see the note in injekt.kt.
 */
package uy.kohesive.injekt.api

interface InjektRegistrar {
    fun <T : Any> addSingleton(key: Class<T>, instance: T)
    fun <T : Any> addSingletonFactory(key: Class<T>, factory: () -> T)
    fun <T : Any> addFactory(key: Class<T>, factory: () -> T)
}

interface InjektModule {
    fun InjektRegistrar.registerInjectables()
}

/**
 * Captures a generic type at the call site. Extensions construct these for
 * generic lookups; only the raw class is ever needed here, because the
 * registry is keyed by raw class.
 */
abstract class TypeReference<T> {
    val type: java.lang.reflect.Type
        get() {
            val superclass = javaClass.genericSuperclass
            return if (superclass is java.lang.reflect.ParameterizedType) {
                superclass.actualTypeArguments[0]
            } else {
                Any::class.java
            }
        }
}

class FullTypeReference<T> : TypeReference<T>()

/** Present so `InjektScope` references resolve; scoping is not modelled. */
open class InjektScope(val registrar: InjektRegistrar)

class DefaultRegistrar : InjektRegistrar {
    private val delegate = uy.kohesive.injekt.Injekt
    override fun <T : Any> addSingleton(key: Class<T>, instance: T) =
        delegate.addSingleton(key, instance)
    override fun <T : Any> addSingletonFactory(key: Class<T>, factory: () -> T) =
        delegate.addSingletonFactory(key, factory)
    override fun <T : Any> addFactory(key: Class<T>, factory: () -> T) =
        delegate.addFactory(key, factory)
}

/** Extensions occasionally name this when building a scope. */
object InjektFactory {
    fun scope(): InjektScope = InjektScope(DefaultRegistrar())
}
