module reactived.util;

import core.thread;

/++
    Implements a Fiber with a return value.

    Use this to pass values asynchronously using the await methods.

    See_Also:
    T await(T)(ValueFiber!T fiber)
    T await(T)(T delegate() dg)
    void await(Fiber fiber)
+/
abstract class ValueFiber(T) : Fiber
{
    private
    {
        T _value;
        Throwable _error;
        bool _hasValue;
    }

    /// Instantiates a new ValueFiber with no value.
    protected this()
    {
        super(&run);
    }

    /// Gets whether a value has been set and no error has been raised.
    bool hasValue() inout @property
    {
        return _hasValue && !hasError;
    }

    /// Gets whether an error has been raised.
    bool hasError() inout @property
    {
        return _error !is null;
    }

    /// Blocks the thread until a value is received.
    T value() @property
    {
        while (!_hasValue)
        {
            this.call();
            if (Fiber.getThis() !is null)
            {
                Fiber.yield();
            }
        }

        if (hasError)
        {
            if (Fiber.getThis() !is null)
            {
                Fiber.yieldAndThrow(_error);
            }
            else
            {
                throw _error;
            }
        }

        return _value;
    }

protected:

    void setValue(T value)
    {
        _value = value;
        _hasValue = true;
    }

    void setError(Throwable error)
    {
        _error = error;
        _hasValue = true;
    }

private:

    void run()
    {
        while (!_hasValue)
        {
            Fiber.yield();
        }
        if (hasError)
        {
            Fiber.yieldAndThrow(_error);
        }
    }
}

/// Waits for fiber to return a value.
T await(T)(ValueFiber!T fiber)
{
    await(cast(Fiber) fiber);

    return fiber.value;
}

/// Waits for dg to return.
T await(T)(T delegate() dg)
{
    class ThreadValueFiber : ValueFiber!T
    {
        this()
        {
            void run()
            {
                auto value = dg();
                setValue(value);
            }

            new Thread(&run).start();
        }
    }

    return await!(T)(new ThreadValueFiber());
}

///
unittest
{
    import std.stdio : writeln;

    int value = await(() => 99);

    writeln(value);

    assert(value == 99, "Value should be 99.");
}

/// Waits for fiber to terminate.
void await(Fiber fiber)
{
    while (fiber.state != Fiber.State.TERM)
    {
        fiber.call();
        if (Fiber.getThis() !is null)
        {
            Fiber.yield();
        }
    }
}
