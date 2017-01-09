module reactived.disposable;

/// Represents a value which can be disposed.
interface Disposable
{
    /// Causes this Disposable to release resources which it has allocated.
    void dispose() @nogc;
}

/// Represents a Disposable which will wait for all references to it to be dropped before disposing.
class RefCountDisposable : Disposable
{
    import std.exception : enforce;

    private
    {
        bool _disposed;
        int _references;

        void delegate() @nogc @trusted _dispose;
    }

    /// Instantiates the RefCountDisposable with the specified dispose delegate.
    this(void delegate() @nogc @trusted dispose) pure @safe nothrow
    {
        _dispose = dispose;
    }

    ~this()
    {
        dispose(false);
    }

    /// Adds a reference to this RefCountDisposable.
    Disposable addReference() @safe
    {
        enforce(!_disposed, "Cannot invoke on a disposed object!");

        ++_references;

        return createDisposable(() => removeReference());
    }

    Disposable addReference(void delegate() @nogc @trusted dg) @safe
    {
        enforce(!_disposed, "Cannot invoke on a disposed object!");

        ++_references;

        return createDisposable(() { removeReference(); dg(); });
    }

    /// Returns whether it is possible to call dispose without any wait.
    bool canDispose() pure inout @nogc @safe @property
    {
        return _references == 0;
    }

    void dispose() @nogc @safe
    {
        dispose(true);
    }

    /// Disposes the RefCountDisposable.
    void dispose(bool disposing) @nogc @safe
    {
        if (_disposed)
        {
            return;
        }
        while (!canDispose)
        {
        }
        _disposed = true;

        if (disposing)
        {
            _dispose();
        }
    }

private:
    void removeReference() @nogc @safe
    {
        assert(!_disposed, "Cannot invoke on a disposed object!");
        assert(_references > 0, "Cannot have negative references!");

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

    refCount.destroy();
}

class CompositeDisposable : Disposable
{
    private
    {
        private bool _disposed;
        Disposable[] _disposables;
    }

    this() @safe nothrow
    {

    }

    this(Disposable[] disposables...) @safe nothrow
    {
        _disposables = disposables.dup;
    }

    ~this()
    {
        dispose(false);
    }

    T opBinary(string op, T)(T rhs)
    {
        return mixin("_disposables " ~ op ~ " rhs");
    }

    int opDollar(size_t pos)()
    {
        return _disposables.opDollar(pos);
    }

    Disposable[] opOpAssign(string op)(Disposable value)
    {
        return mixin("_disposables" ~ op ~ "value");
    }

    Disposable opIndex(size_t index)
    {
        return _disposables[index];
    }

    void opIndexAssign(size_t index, Disposable value)
    {
        _disposables[index] = value;
    }

    void add(Disposable disposable)
    {
        _disposables ~= disposable;
    }

    void dispose() @nogc
    {
        dispose(true);
    }

    private void dispose(bool disposing) @nogc
    {
        synchronized
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;

            if (!disposing)
            {
                return;
            }

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
}

unittest
{
    auto composite = new CompositeDisposable();
    auto refCount = new RefCountDisposable({  });

    composite.add(createDisposable(() @nogc{
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
    private Disposable _disposable;

    this() @safe nothrow
    {
        this(empty);
    }

    this(Disposable wrap) @safe nothrow
    {
        _disposable = wrap;
    }

    this(void delegate() @nogc dispose) @safe nothrow
    {
        this(createDisposable(dispose));
    }

    ~this()
    {
        dispose(false);
    }

    bool isDisposed() inout @safe @property
    {
        return _isDisposed;
    }

    void dispose() @nogc
    {
        dispose(true);
    }

    void dispose(bool disposing) @nogc
    {
        synchronized
        {
            if (!_isDisposed)
            {
                _isDisposed = true;
                if (disposing)
                {
                    _disposable.dispose();
                }
            }
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
    @nogc @safe pure nothrow this(string file = __FILE__, size_t line = __LINE__,
            Throwable next = null)
    {
        super("Cannot access a disposed object", file, line, next);
    }

    /// ditto
    @nogc @safe pure nothrow this(Throwable next, string file = __FILE__, size_t line = __LINE__)
    {
        super("Cannot access a disposed object", file, line, next);
    }
}

AssignmentDisposable!Disposable assignmentDisposable(Disposable value = empty) pure @safe nothrow
{
    return new AssignmentDisposable!Disposable(value);
}

AssignmentDisposable!T assignmentDisposable(T : Disposable)(T value) pure @safe nothrow
{
    return new AssignmentDisposable!T(value);
}

AssignmentDisposable!T assignmentDisposable(T : Disposable)() @safe nothrow 
        if (is(typeof(new T()) : T))
{
    return new AssignmentDisposable!T();
}

class AssignmentDisposable(TDisposable : Disposable) : Disposable
{
    private
    {
        bool _disposed;
        TDisposable _dispose;
    }

    alias disposable this;

    static if (is(typeof(new TDisposable()) : Disposable))
    {
        package this() @safe nothrow
        {
            this(new TDisposable());
        }
    }

    static if (is(TDisposable == Disposable))
    {
        package this() @safe nothrow
        {
            this(empty());
        }
    }

    package this(TDisposable value)
    {
        _dispose = value;
    }

    ~this()
    {
        dispose(false);
    }

    TDisposable disposable() @nogc @safe @property
    {
        return _dispose;
    }

    void disposable(TDisposable value) @nogc @trusted @property
    {
        if (_disposed)
        {
            value.dispose();
            return;
        }

        _dispose.dispose();
        _dispose = value;
    }

    void opAssign(TDisposable value) @safe
    {
        disposable = value;
    }

    void dispose() @nogc
    {
        dispose(true);
    }

    void dispose(bool disposing) @nogc
    {
        synchronized
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;

            if (disposing)
            {
                _dispose.dispose();
            }
        }
    }
}

unittest
{
    auto assignment = assignmentDisposable();

    bool disposed1, disposed2;

    assignment = createDisposable({ disposed1 = true; });
    //assignment = new BooleanDisposable({ disposed2 = true; });

    //assert(disposed1);

    assignment.dispose();

    //assert(disposed2);
}

unittest
{
    auto assignment = assignmentDisposable!BooleanDisposable();

    assert(!assignment.isDisposed);

    auto disposable = assignment.disposable;

    assert(!disposable.isDisposed);

    assignment = new BooleanDisposable();

    assert(disposable.isDisposed);

    assignment.dispose();

    assert(assignment.isDisposed);
}

/// Creates a Disposable which has the provided onDisposed delegate as its dispose method.
Disposable createDisposable(void delegate() @nogc onDisposed) @safe nothrow
{
    static class AnonymousDisposable : Disposable
    {
        private bool _disposed;
        private void delegate() @nogc _onDisposed;

        this(void delegate() @nogc onDisposed) nothrow
        {
            _onDisposed = onDisposed;
        }

        ~this()
        {
            dispose(false);
        }

        void dispose() @nogc @trusted
        {
            dispose(true);
        }

        void dispose(bool disposing) @nogc @trusted
        {
            synchronized
            {
                if (!_disposed)
                {
                    _disposed = true;
                    if (disposing)
                    {
                        _onDisposed();
                    }
                }
            }
        }
    }

    return new AnonymousDisposable(onDisposed);
}

/// Creates a Disposable which has the provided onDisposed function as its dispose method.
Disposable createDisposable(void function() @nogc onDisposed) @safe nothrow
{
    static class AnonymousDisposable : Disposable
    {
        private bool _disposed;
        void function() @nogc _onDisposed;

        this(void function() @nogc onDisposed)
        {
            _onDisposed = onDisposed;
        }

        ~this()
        {
            dispose(false);
        }

        void dispose() @nogc @trusted
        {
            dispose(true);
        }

        void dispose(bool disposing) @nogc @trusted
        {
            synchronized
            {
                if (!_disposed)
                {
                    _disposed = true;
                    if (disposing)
                    {
                        _onDisposed();
                    }
                }
            }
        }
    }

    return new AnonymousDisposable(onDisposed);
}

/// Creates an empty Disposable.
Disposable empty() @safe nothrow
{
    static void dispose() nothrow @safe @nogc
    {

    }

    return createDisposable(&dispose);
}
