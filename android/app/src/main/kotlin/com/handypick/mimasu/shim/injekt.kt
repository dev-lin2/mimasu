@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * Injekt API surface, provided by the host.
 *
 * Extensions call `Injekt.get<NetworkHelper>()` and `injectLazy()` to obtain
 * things the host owns (docs/phase-0-findings.md §4 confirms
 * uy.kohesive.injekt.InjektKt, .api.InjektScope, .api.InjektFactory and
 * .api.FullTypeReference are referenced by a real extension).
 *
 * This reproduces the *signatures* extensions compile against, with our own
 * behaviour behind them — see INSTRUCTIONS.md §13. The original library is
 * Apache-2.0; nothing here is copied from it.
 *
 * Deliberately not a general DI container: it is a type-keyed singleton
 * registry, which is all an extension ever asks of it.
 */
package uy.kohesive.injekt

import uy.kohesive.injekt.api.InjektModule
import uy.kohesive.injekt.api.InjektRegistrar

object Injekt : InjektRegistrar {

    private val singletons = LinkedHashMap<String, Any>()
    private val factories = LinkedHashMap<String, () -> Any>()

    @Synchronized
    override fun <T : Any> addSingleton(key: Class<T>, instance: T) {
        singletons[key.name] = instance
    }

    @Synchronized
    override fun <T : Any> addSingletonFactory(key: Class<T>, factory: () -> T) {
        @Suppress("UNCHECKED_CAST")
        factories[key.name] = factory as () -> Any
    }

    @Synchronized
    override fun <T : Any> addFactory(key: Class<T>, factory: () -> T) {
        @Suppress("UNCHECKED_CAST")
        factories[key.name] = factory as () -> Any
    }

    @Synchronized
    fun <T : Any> getInstance(key: Class<T>): T {
        singletons[key.name]?.let {
            @Suppress("UNCHECKED_CAST")
            return it as T
        }
        val factory = factories[key.name]
            ?: throw IllegalStateException(
                "Nothing registered for ${key.name}. The host must register it " +
                    "before instantiating a source (INSTRUCTIONS.md 5.2).",
            )
        val created = factory()
        singletons[key.name] = created
        @Suppress("UNCHECKED_CAST")
        return created as T
    }

    @Synchronized
    fun clear() {
        singletons.clear()
        factories.clear()
    }

    fun importModule(module: InjektModule) = module.run { registerInjectables() }

    inline fun <reified T : Any> get(): T = getInstance(T::class.java)
}

/** `Injekt.get<T>()` at top level, which is how extensions usually spell it. */
inline fun <reified T : Any> injectLazy(): Lazy<T> =
    lazy(LazyThreadSafetyMode.SYNCHRONIZED) { Injekt.get<T>() }

inline fun <reified T : Any> injectValue(): T = Injekt.get<T>()
