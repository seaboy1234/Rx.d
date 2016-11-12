module reactived.observable.generators;

import reactived.observer;
import reactived.disposable : Disposable, createDisposable;
import reactived.observable;

import disposable = reactived.disposable;
import std.functional;
import std.traits;
import std.range.primitives;

/// Create an Observable sequence from a Subscribe method.
Observable!T create(T)(Disposable delegate(Observer!T) subscribe) pure @safe
{
    static class AnonymousObservable : Observable!T
    {
        private Disposable delegate(Observer!T) _subscribe;

        this(Disposable delegate(Observer!T) subscribe)
        {
            _subscribe = subscribe;
        }

        Disposable subscribe(Observer!T observer)
        {
            return _subscribe(observer);
        }
    }

    return new AnonymousObservable(subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    Disposable subscribe(Observer!int observer)
    {
        observer.onNext(1);
        observer.onNext(2);
        observer.onNext(3);

        observer.onCompleted();

        return disposable.empty();
    }

    auto observable = create(&subscribe);

    observable.subscribe(value => writeln("observer.onNext(", value, ")"),
            () => writeln("observer.onCompleted()"));

    /++
        Output:

        observer.onNext(1)
        observer.onNext(2)
        observer.onNext(3)
        observer.onCompleted()
    +/
}

/++
 + Creates an Observable sequence using the provided subscribe method.
 +
 + This differs from the other create method in that the subscribe method returns 
 + a delegate which will be wrapped with createDisposable().
 + 
 + See_Also:
 + create(T)(Disposable delegate(Observer!T))
 +/
Observable!T create(T)(void delegate() delegate(Observer!T) subscribe) pure @safe
{
    Disposable subscribe_(Observer!T observer)
    {
        return createDisposable(subscribe(observer));
    }

    return create(&subscribe_);
}

///
unittest
{
    import std.stdio : writeln;

    void delegate() subscribe(Observer!int observer)
    {
        observer.onNext(1);
        observer.onNext(2);
        observer.onNext(3);

        observer.onCompleted();

        return {  };
    }

    auto observable = create(&subscribe);

    observable.subscribe(value => writeln("observer.onNext(", value, ")"),
            () => writeln("observer.onCompleted()"));

    /++
        Output:

        observer.onNext(1)
        observer.onNext(2)
        observer.onNext(3)
        observer.onCompleted()
    +/
}

/++
    Creates on Observable sequence which emits an error.
+/
Observable!T error(T)(Throwable error) pure @safe
{
    Disposable subscribe(Observer!T observer)
    {
        observer.onError(error);

        return disposable.empty();
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    error!int(new Exception("Test")).subscribe(value => writeln(value),
            error => writeln("Error: ", error.msg));

    // => Error: Test
}

/// Creates an observable which emits no elements and never completes.
Observable!T never(T)() pure @safe
{
    Disposable subscribe(Observer!T)
    {
        return disposable.empty();
    }

    return create(&subscribe);
}

/// Create an Observable sequence which emits only a single value.
Observable!T single(T)(T value) pure @safe
{
    Disposable subscribe(Observer!T observer)
    {
        import core.thread : Fiber;

        observer.onNext(value);
        observer.onCompleted();

        return disposable.empty();
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    single("single value").subscribe(value => writeln(value), () => writeln("completed"));

    /++
        Output:

        single value
        completed
    +/
}

/// Creates an Observable which emits no elements and completes immediately.
Observable!T empty(T)() pure @safe
{
    Disposable subscribe(Observer!T observer)
    {
        observer.onCompleted();

        return disposable.empty();
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    empty!(int).subscribe(value => writeln(value), () => writeln("completed"));

    /++
        Output:
        completed
    +/
}

/// Create an Observable sequence which emits a range of numerics.
Observable!T range(T)(T start, T count) pure @safe if (isNumeric!T)
{
    return unfold!(T, T)(start, v => v < count, v => v + 1, v => v);
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).subscribe(value => writeln(value));

    /++
        Output:
        0
        1
        2
        ...
        7
        8
        9
    +/
}

/// Create an Observable sequence using an InputRange.
Observable!(ElementType!Range) asObservable(Range)(Range range) pure @safe
{
    Disposable subscribe(Observer!(ElementType!Range) observer)
    {
        bool exited;
        scope (exit)
        {
            foreach (value; range)
            {
                if (exited)
                {
                    break;
                }
                observer.onNext(value);
            }
            if (!exited)
            {
                observer.onCompleted();
            }
        }
        return disposable.createDisposable({ exited = true; });
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    string[] arr = ["this", "is", "a", "sample", "range"];

    arr.asObservable().subscribe(value => writeln(value), () => writeln("completed"));

    /++
        Output:

        this
        is
        a
        sample
        range
        completed
    +/
}

/++
    Creates an Observable sequence which lazily evaluates action.

    action will only be invoked once--on the first subscription of an Observer--and the value cached.

    See_Also:
    Observable!Unit start(F)(F action)
+/
Observable!(ReturnTypeOrUnit!(F)) start(F)(F action) if (isCallable!F)
{
    import reactived.subject : Subject;

    static import std.parallelism;

    enum isVoid = is(typeof(action()) == void);

    static if (!isVoid)
    {
        alias T = typeof(action());
    }
    else
    {
        alias T = Unit;
    }

    class StartObservable : Subject!(T)
    {
        T value;
        bool hasValue;
        bool started;

        override Disposable subscribe(Observer!(T) observer)
        {
            if (!started)
            {
                T run() @trusted
                {
                    static if (isVoid)
                    {
                        action();
                        setValue(Unit());
                        return Unit();
                    }
                    else
                    {
                        auto value = action();
                        setValue(value);
                        return value;
                    }
                }

                started = true;

                auto t = std.parallelism.task(&run);
                t.executeInNewThread();
            }
            if (hasValue)
            {
                observer.onNext(value);
                observer.onCompleted();
                return disposable.empty();
            }
            return super.subscribe(observer);
        }

    private:
        void setValue(T val)
        {
            hasValue = true;
            static if (!isVoid)
            {
                value = val;
            }
            onNext(val);
            onCompleted();
        }
    }

    return new StartObservable();
}

///
unittest
{
    import std.stdio : writeln;

    static int test()
    {
        import core.thread : Thread;
        import std.datetime : dur;

        Thread.sleep(dur!"seconds"(1));

        return 3;
    }

    start(() => true).subscribe(value => assert(value, "value should be true."));

    start(&test).subscribe(value => assert(value == 3, "value should be 3."));

    void test2(int)
    {
        assert(0, "should not be called");
    }

    auto testStart = start(&test);

    testStart.subscribe(&test2).dispose();

    testStart.subscribe(value => assert(value == 3, "value should be 3."));

    static void test3()
    {
        import core.thread : Thread;
        import std.datetime : dur;

        Thread.sleep(dur!"seconds"(1));
    }

    bool published;

    void setPublished(Unit)
    {
        published = true;
    }

    start(&test3).subscribe(&setPublished, () => assert(published, "onNext should be called."));

    while (!published)
    {
    }
}

template ReturnTypeOrUnit(F) if (isCallable!F)
{
    static if (is(typeof(F.init()) == void))
    {
        alias ReturnTypeOrUnit = typeof(Unit());
    }
    else
    {
        alias ReturnTypeOrUnit = typeof(F.init());
    }
}

Observable!T unfold(T, Result)(T seed, bool delegate(T) condition,
        T delegate(T) iterate, Result delegate(T) resultSelector)
{
    auto subscribe(Observer!T observer)
    {
        bool disposed;
        T current = seed;

        do
        {
            try
            {
                observer.onNext(resultSelector(current));
            }
            catch (Exception e)
            {
                observer.onError(e);
            }
            current = iterate(current);
        }
        while (!disposed && condition(current));

        observer.onCompleted();

        return { disposed = true; };
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : dump;

    unfold!(int, int)(1, v => v < 25, v => v + 1, v => v).dump("unfold(1)");
    unfold!(int, int)(1, v => v < 100, v => v + 1, v => v).take(10).dump("unfold(1).take(10)");
}
