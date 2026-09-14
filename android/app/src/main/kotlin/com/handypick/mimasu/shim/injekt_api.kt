@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * uy.kohesive.injekt.api — the types extensions name when they touch Injekt.
 *
 * Signatures only, our own behaviour behind them (INSTRUCTIONS.md §13).
 *
 * The shape here is not a guess: a real extension failed with
 *   NoSuchMethodError: No static method getInjekt()Luy/kohesive/injekt/api/InjektScope;
 *     in class Luy/kohesive/injekt/InjektKt
 * which says `Injekt` is a top-level *property* of type [InjektScope], not an
 * object. Kotlin compiles such a property to `InjektKt.getInjekt()`.
 */
package uy.kohesive.injekt.api

import java.lang.reflect.ParameterizedType
import java.lang.reflect.Type

interface InjektRegistrar {
    fun <T : Any> addSingleton(key: Class<T>, instance: T)
    fun <T : Any> addSingletonFactory(key: Class<T>, factory: () -> T)
    fun <T : Any> addFactory(key: Class<T>, factory: () -> T)
}

interface InjektModule {
    fun InjektRegistrar.registerInjectables()
}

/**
 * Captures a generic type at the call site. Extensions construct anonymous
 * subclasses of [FullTypeReference] through Injekt's inlined `fullType()`, so
 * these must stay open.
 */
abstract class TypeReference<T> {
    val type: Type
        get() {
            val superclass = javaClass.genericSuperclass
            return if (superclass is ParameterizedType) {
                superclass.actualTypeArguments[0]
            } else {
                Any::class.java
            }
        }
}

open class FullTypeReference<T> : TypeReference<T>()

/**
 * A type-keyed singleton registry. Deliberately not a general DI container:
 * a source only ever asks for NetworkHelper, SharedPreferences or a Context.
 */
open class InjektScope : InjektRegistrar, InjektFactory {

    private val singletons = LinkedHashMap<String, Any>()
    private val factories = LinkedHashMap<String, () -> Any>()

    @Synchronized
    override fun <T : Any> addSingleton(key: Class<T>, instance: T) {
        singletons[key.name] = instance
    }

    @Synchronized
    @Suppress("UNCHECKED_CAST")
    override fun <T : Any> addSingletonFactory(key: Class<T>, factory: () -> T) {
        factories[key.name] = factory as () -> Any
    }

    @Synchronized
    @Suppress("UNCHECKED_CAST")
    override fun <T : Any> addFactory(key: Class<T>, factory: () -> T) {
        factories[key.name] = factory as () -> Any
    }

    @Synchronized
    @Suppress("UNCHECKED_CAST")
    override fun <T : Any> getInstance(key: Class<T>): T {
        singletons[key.name]?.let { return it as T }
        val factory = factories[key.name]
            ?: throw IllegalStateException(
                "Nothing registered for ${key.name}. The host must register it " +
                    "before instantiating a source (INSTRUCTIONS.md 5.2).",
            )
        val created = factory()
        singletons[key.name] = created
        return created as T
    }

    /** Generic lookups arrive as a Type; only the raw class is ever needed. */
    override fun <T : Any> getInstance(type: Type): T {
        val raw = when (type) {
            is ParameterizedType -> type.rawType
            else -> type
        }
        @Suppress("UNCHECKED_CAST")
        return getInstance(raw as Class<Any>) as T
    }

    override fun <T : Any> getInstance(reference: TypeReference<T>): T =
        getInstance<T>(reference.type)

    inline fun <reified T : Any> get(): T = getInstance(T::class.java)

    fun importModule(module: InjektModule) = module.run { registerInjectables() }

    @Synchronized
    fun clear() {
        singletons.clear()
        factories.clear()
    }
}

/**
 * An interface, not an object: a real extension failed with
 *   IncompatibleClassChangeError: Found class ...InjektFactory, but interface
 *   was expected
 * which says [InjektScope] implements it rather than it being a singleton.
 */
interface InjektFactory {
    fun <T : Any> getInstance(key: Class<T>): T
    fun <T : Any> getInstance(type: Type): T
    fun <T : Any> getInstance(reference: TypeReference<T>): T
}

fun <T> fullType(): FullTypeReference<T> = FullTypeReference()
