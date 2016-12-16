module reactived.util;

import std.range;

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

import reactived.observable;
import reactived.disposable;

/**
    Dumps values of the provided observable to stdout in the format `name => value`.
*/
Disposable dump(T)(Observable!T observable, string name)
{
    import std.stdio : writeln;

    // dfmt off
    return observable.subscribe(
            val => writeln(name, " => ", val),
            () => writeln(name, " => completed"), 
            e => writeln(name, " => Error: ", e));
    // dfmt on
}

unittest
{
    import reactived.subject : Subject;

    Subject!int s = new Subject!int();

    auto sub = s.dump("s");

    s.onNext(1);
    s.onNext(2);
    s.onNext(5);
    s.onCompleted();

    s = new Subject!int();

    sub = s.dump("s");

    s.onError(new Exception("It failed."));
}

Observable!T transparentDump(T)(Observable!T source, string name)
{
    import reactived : doOnEach;
    import std.stdio : writeln;

    // dfmt off
    return source.doOnEach(
        (T val) => writeln(name, " => ", val),
        ()      => writeln(name, " => completed"), 
        e       => writeln(name, " => Error: ", e)
    );

     // dfmt on
}

void assertEqual(T, Range)(Observable!T source, Range range, string message) if (isInputRange!Range && is(ElementType!Range == T))
{
    assert(source.sequenceEqual(range).wait(), message);
}

class LinkedQueue(T)
{
@safe:
    private static struct Node
    {
        T data;
        Node* next;
    }

    private Node* head, tail;

    alias enqueue = push;
    alias dequeue = pop;

    bool empty() @property nothrow
    {
        return head is null;
    }

    void push(T item) nothrow
    {
        if (empty())
        {
            head = tail = new Node(item);
        }
        else
        {
            tail.next = new Node(item);
            tail = tail.next;
        }
    }

    T pop()
    {
        if (empty)
        {
            throw new Exception("Cannot pop an empty LinkedQueue.");
        }

        T item = head.data;
        head = head.next;

        if (head is tail)
        {
            tail = null;
        }

        return item;
    }
}
