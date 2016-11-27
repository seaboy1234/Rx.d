module reactived.disposable;

/// Represents a value which can be disposed.
interface Disposable
{
    /// Causes this Disposable to release resources which it has allocated.
    void dispose();
}

/// Represents a Disposable which will wait for all references to it to be dropped before disposing.
class RefCountDisposable : Disposable
{
    import std.exception : enforce;

    private
    {
        bool _disposed;
        int _references;

        void delegate() @trusted _dispose;
    }

    /// Instantiates the RefCountDisposable with the specified dispose delegate.
    this(void delegate() @trusted dispose) pure
    {
        _dispose = dispose;
    }

    /// Adds a reference to this RefCountDisposable.
    Disposable addReference() @safe
    {
        enforce(!_disposed, "Cannot invoke on a disposed object!");

        ++_references;

        return createDisposable(() => removeReference());
    }

    /// Returns whether it is possible to call dispose without any wait.
    bool canDispose() pure inout @safe @property
    {
        return _references == 0 && !_disposed;
    }

    /// Disposes the RefCountDisposable.
    void dispose() @safe
    {
        while (!canDispose)
        {
        }
        _disposed = true;

        _dispose();
    }

private:
    void removeReference() @safe
    {
        enforce(!_disposed, "Cannot invoke on a disposed object!");
        enforce(_references > 0, "Cannot have negative references!");

        --_references;
    }
}

unittest
{
    bool called;
    void dispose() @trusted
    {
        called = true;
    }

    auto refCount = new RefCountDisposable(&dispose);

    assert(refCount.canDispose(), "refCount has no references.");

    auto d1 = refCount.addReference();

    assert(!refCount.canDispose(), "refCount has references.");

    d1.dispose();

    assert(refCount.canDispose(), "references are disposed.");

    refCount.dispose();

    assert(called, "dispose was called.");
}

class CompositeDisposable : Disposable
{
    private
    {
        Disposable[] _disposables;
    }

    this()
    {

    }

    this(Disposable[] disposables...)
    {
        _disposables = disposables.dup;
    }

    void add(Disposable disposable)
    {
        _disposables ~= disposable;
    }

    void dispose()
    {
        try
        {
            foreach (value; _disposables)
            {
                value.dispose();
            }
        }
        finally
        {
            _disposables = Disposable[].init;
        }
    }
}

unittest
{
    auto composite = new CompositeDisposable();
    auto refCount = new RefCountDisposable({  });

    composite.add(createDisposable({
            assert(!refCount.canDispose(), "refCount has references.");
        }));

    auto d1 = refCount.addReference();

    composite.add(d1);

    composite.add(refCount);

    composite.dispose();
}

class BooleanDisposable : Disposable
{
    import core.sync.mutex : Mutex;

    private bool _isDisposed;
    private void delegate() _dispose;
    private Mutex _mutex;

    this()
    {
        this(empty);
    }

    this(Disposable wrap)
    {
        this(&wrap.dispose);
    }

    this(void delegate() dispose)
    {
        _dispose = dispose;
        _mutex = new Mutex(this);
    }

    bool isDisposed() inout @safe @property
    {
        synchronized (_mutex)
        {
            return _isDisposed;
        }
    }

    void dispose()
    {
        synchronized (_mutex)
        {
            _isDisposed = true;
            _dispose();
        }
    }
}

class ObjectDisposedException : Exception
{
    /**
     * Creates a new instance of ObjectDisposedException. The next parameter 
     * is used internally and should always be $(D null) when passed by user 
     * code. This constructor does not automatically throw the newly-created
     * Exception; the $(D throw) statement should be used for that purpose.
     */
    @nogc @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super("Cannot access a disposed object", file, line, next);
    }

    /// ditto
    @nogc @safe pure nothrow this(Throwable next, string file = __FILE__, size_t line = __LINE__)
    {
        super("Cannot access a disposed object", file, line, next);
    }
}

class AssignmentDisposable : Disposable
{
    private
    {
        bool _disposed;
        Disposable _dispose;
    }

    this()
    {
        this(empty());
    }

    this(Disposable value)
    {
        _dispose = value;
    }

    Disposable disposable() @property
    {
        if(_disposed)
        {
            throw new ObjectDisposedException();
        }

        return _dispose;
    }

    void disposable(Disposable value) @property
    {
        _dispose.dispose();
        _dispose = value;
    }

    void dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _dispose.dispose();
    }
}

/// Creates a Disposable which has the provided onDisposed delegate as its dispose method.
Disposable createDisposable(void delegate() onDisposed) @safe
{
    class AnonymousDisposable : Disposable
    {
        void dispose() @trusted
        {
            onDisposed();
        }
    }

    return new AnonymousDisposable();
}

/// Creates a Disposable which has the provided onDisposed function as its dispose method.
Disposable createDisposable(void function() onDisposed) @safe
{
    class AnonymousDisposable : Disposable
    {
        void dispose() @trusted
        {
            onDisposed();
        }
    }

    return new AnonymousDisposable();
}

/// Creates an empty Disposable.
Disposable empty() @safe
{
    static void dispose() nothrow @safe
    {

    }

    return createDisposable(&dispose);
}
