module reactived.util;

struct List(T)
{
    private
    {
        T[] items = [T.init];
        size_t length;
    }

    alias range this;

    this(T[] items_)
    {
        items = items_;
        length = items.length;
    }

    auto range()
    {
        struct ListRange
        {
            private
            {
                size_t index;
                List!T list;
            }

            this(List!T list_)
            {
                list = list_;
            }

            T front() @property
            {
                return list[index];
            }

            T back() @property
            {
                return list[list.length - index];
            }

            void popFront()
            {
                index++;
            }

            void popBack()
            {
                index++;
            }

            bool empty() @property
            {
                return index >= list.length;
            }

            typeof(this) save() @property
            {
                return this;
            }
        }

        return ListRange(this);
    }

    void add(T item)
    {
        if (length >= items.length)
        {
            items.length *= 2;
        }
        items[length++] = item;
    }

    void remove(T item)
    {
        size_t index = indexOf(item);
        if (index == -1)
        {
            return;
        }
        removeAt(index);
    }

    void removeAt(size_t index)
    {
        if (index == length - 1)
        {
            length--;
            items[index] = T.init;
            return;
        }

        for (size_t i = index; i < length - 2; i++)
        {
            items[i] = items[i + 1];
        }
        length--;
        if (items.length < length / 2)
        {
            items.length /= 2;
        }
    }

    void clear()
    {
        items = T[].init;
        length = 0;
    }

    size_t indexOf(T item)
    {
        foreach (index, value; items)
        {
            if (item == value)
            {
                return index;
            }
        }
        return -1;
    }

    T opIndex(size_t index)
    in
    {
        assert(index < length);
        assert(index >= 0);
    }
    body
    {
        return items[index];
    }

    void opIndexAssign(size_t index, T value)
    {
        items[index] = value;
    }

    T opIndexUnary(string op)()
    {
        mixin(op ~ items);
    }
}

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
            if(Fiber.getThis() !is null)
            {
                Fiber.yield();
            }
        }

        if (hasError)
        {
            if(Fiber.getThis() !is null)
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
    await(cast(Fiber)fiber);

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
