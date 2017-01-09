module reactived.observable.generators;

import std.functional;
import std.traits;
import std.range.primitives;
import std.datetime;

import reactived.observer;
import reactived.disposable : Disposable, BooleanDisposable, createDisposable;
import reactived.observable;
import reactived.scheduler;

import disposable = reactived.disposable;

/// Create an Observable sequence from a Subscribe method.
Observable!T create(T)(Disposable delegate(Observer!T) subscribe) pure @safe nothrow
{
    static class AnonymousObservable : ObservableBase!T
    {
        private Disposable delegate(Observer!T) _subscribe;

        this(Disposable delegate(Observer!T) subscribe)
        {
            _subscribe = subscribe;
        }

        override Disposable subscribeCore(Observer!T observer)
        {
            return _subscribe(observer);
        }
    }

    return new AnonymousObservable(subscribe);
}

///
unittest
{
    import reactived.util : assertEqual;

    Disposable subscribe(Observer!int observer)
    {
        observer.onNext(1);
        observer.onNext(2);
        observer.onNext(3);

        observer.onCompleted();

        return disposable.empty();
    }

    auto observable = create(&subscribe);

    observable.assertEqual([1, 2, 3]);
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
Observable!T create(T)(void delegate() @nogc delegate(Observer!T) subscribe) pure @safe nothrow
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
    import reactived.util : assertEqual;

    void delegate() @nogc subscribe(Observer!int observer)
    {
        observer.onNext(1);
        observer.onNext(2);
        observer.onNext(3);

        observer.onCompleted();

        return {  };
    }

    auto observable = create(&subscribe);

    observable.assertEqual([1, 2, 3]);
}

/++
    Creates on Observable sequence which emits an error.
+/
Observable!T error(T)(Throwable error) pure @safe nothrow
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
    import reactived.util : dump;

    error!int(new Exception("Test")).dump("Error");

    // => Error: Test
}

/// Creates an observable which emits no elements and never completes.
Observable!T never(T)() pure @safe nothrow
{
    Disposable subscribe(Observer!T)
    {
        return disposable.empty();
    }

    return create(&subscribe);
}

alias single = just;

/// Create an Observable sequence which emits only a single value.
Observable!T just(T)(T value) pure @safe nothrow
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
    import reactived.util : assertEqual;

    just("this").assertEqual(["this"]);
}

/// Creates an Observable which emits no elements and completes immediately.
Observable!T empty(T)() pure @safe nothrow
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
Observable!T range(T)(T start, T count, T step = 1) pure @safe nothrow 
        if (isNumeric!T)
{
    return unfold!(T, T)(start, v => v - start < count * step, v => v + step, v => v);
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

    range(10, 10).length().subscribe(count => assert(count == 10));

    range(0, 4, 2).sequenceEqual([0, 2, 4, 6]).subscribe(x => assert(x));

    range(0, 5).sequenceEqual([0, 1, 2, 3, 4]).subscribe(x => assert(x));
}

/**
    Transforms a function call into an Observable which completes when the call completes.
*/
template start(alias fun, Args...) if (isCallable!fun)
{
    alias ReturnType = typeof(fun(Args.init));
    static if (is(ReturnType == void))
    {
        alias T = Unit;
    }
    else
    {
        alias T = ReturnType;
    }
    Observable!T start(Args args)
    {
        Disposable subscribe(Observer!T observer)
        {
            BooleanDisposable subscription = new BooleanDisposable();
            taskScheduler.run(() {
                try
                {
                    static if (!is(ReturnType == void))
                    {
                        ReturnType value = fun(args);
                        if (!subscription.isDisposed())
                        {
                            observer.onNext(value);
                        }

                    }
                    else
                    {
                        fun(Args);
                        if (!subscription.isDisposed())
                        {
                            observer.onNext(Unit());
                        }
                    }
                }
                catch (Exception e)
                {
                    if (!subscription.isDisposed)
                    {
                        observer.onError(e);
                    }
                }
                if (!subscription.isDisposed)
                {
                    observer.onCompleted();
                }
            });

            return subscription;
        }

        return create(&subscribe);
    }
}

///
unittest
{
    import std.stdio : writeln;
    import reactived.util : assertEqual;

    static int test()
    {
        import core.thread : Thread;
        import std.datetime : dur;

        Thread.sleep(dur!"seconds"(1));

        return 3;
    }

    start!(() => true).subscribe(value => assert(value, "value should be true."));

    start!test().subscribe(value => assert(value == 3, "value should be 3."));

    void test2(int)
    {
        assert(0, "should not be called");
    }

    auto testStart = start!test();

    testStart.subscribe(&test2).dispose();

    testStart.assertEqual([3], "value should be 3.");

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

    start!test3().subscribe(&setPublished, () => assert(published, "onNext should be called."));

    while (!published)
    {
    }
    published = false;

    int multiArgs(int a, int b)
    {
        assert(!published);
        published = true;
        return a + b;
    }

    start!multiArgs(2, 3).assertEqual([5]);
    assert(published);
}

Observable!T unfold(T, Result)(T seed, bool delegate(T) condition,
        T delegate(T) iterate, Result delegate(T) resultSelector)
{
    auto subscribe(Observer!T observer)
    {
        bool disposed;
        T current = seed;

        while (!disposed && condition(current))
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

        observer.onCompleted();

        return { disposed = true; };
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : transparentDump;
    import reactived : asRange;
    import std.range : iota;

    // dfmt off
    unfold!(int, int)(1, v => v < 25, v => v + 1, v => v).transparentDump("unfold(1)")
                                                         .sequenceEqual(iota(1, 25))
                                                         .subscribe(x => assert(x));

    unfold!(int, int)(1, v => v < 100, v => v + 1, v => v).take(10)
                                                          .transparentDump("unfold(1).take(10)")
                                                          .sequenceEqual(iota(1, 11))
                                                          .subscribe(x => assert(x));
    // dfmt on

    unfold!(int, int)(1, v => v < 1, v => v + 1, v => v).sequenceEqual(empty!int()
            .asRange).subscribe(v => assert(v));
}

Observable!size_t interval(Duration duration)
{
    return interval(duration, taskScheduler);
}

Observable!size_t interval(Duration duration, Scheduler scheduler)
{
    import core.thread : Thread;

    Disposable subscribe(Observer!size_t observer)
    {
        size_t state;
        disposable.BooleanDisposable subscription = new disposable.BooleanDisposable();
        scheduler.run((self) {
            Thread.getThis().sleep(duration);
            observer.onNext(state++);

            if (!subscription.isDisposed)
            {
                self();
            }
        });

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    bool completed;
    interval(dur!"msecs"(10)).take(10).subscribe(v => assert(v < 10), () {
        completed = true;
    });

    while (!completed)
    {
    }

    // FAILS: Runs forever despite completing. 
    // interval(dur!"msecs"(10), newThreadScheduler).take(10).subscribe(v => assert(v < 10));
}

Observable!size_t timer(Duration start)
{
    return timer(start, taskScheduler);
}

Observable!size_t timer(Duration start, Scheduler scheduler)
{
    import core.thread : Thread;

    Disposable subscribe(Observer!size_t observer)
    {
        disposable.BooleanDisposable subscription = new disposable.BooleanDisposable();

        scheduler.run(() {
            Thread.getThis().sleep(start);

            if (!subscription.isDisposed)
            {
                observer.onNext(0);
                observer.onCompleted();
            }
        });

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    assert(timer(dur!"msecs"(100)).wait() == 0);
}

Observable!size_t timer(Duration start, Duration period)
{
    return timer(start, period, taskScheduler);
}

Observable!size_t timer(Duration start, Duration period, Scheduler scheduler)
{
    import core.thread : Thread;

    Disposable subscribe(Observer!size_t observer)
    {
        size_t state;
        disposable.BooleanDisposable subscription = new disposable.BooleanDisposable();
        scheduler.run({
            Thread.getThis().sleep(start);

            scheduler.run((self) {
                observer.onNext(state++);
                Thread.getThis().sleep(period);

                if (!subscription.isDisposed)
                {
                    self();
                }
            });
        });

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    bool completed;

    timer(dur!"msecs"(10), dur!"msecs"(10)).take(10).subscribe(v => assert(v < 10), () {
        completed = true;
    });
}

typeof(fun()) defer(alias fun)()
        if (isCallable!fun && isObservable!((ReturnType!fun)))
{
    alias T = ReturnType!(fun).ElementType;

    Disposable subscribe(Observer!T observer)
    {
        return fun().subscribe(observer);
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : assertEqual, transparentDump;

    int k;
    Observable!int observable = defer!(() => single(++k));
    Observable!int control = single(++k);

    foreach (i; 2 .. 10)
    {
        observable.transparentDump("defer").assertEqual([i]);
        control.transparentDump("control").assertEqual([1]);
    }
}

Observable!(ElementType!Range) repeat(Range)(Range items,
        size_t repeatCount = -1, Scheduler scheduler = taskScheduler)
        if (isForwardRange!Range)
{
    alias T = ElementType!Range;

    Disposable subscribe(Observer!T observer)
    {
        size_t localCount = repeatCount;
        BooleanDisposable subscription = new BooleanDisposable();

        scheduler.run((self) {
            if (localCount-- == 0)
            {
                observer.onCompleted();
                return;
            }
            foreach (value; items.save)
            {
                if (subscription.isDisposed)
                {
                    return;
                }
                observer.onNext(value);
            }
            self();
        });

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : transparentDump, assertEqual;

    // dfmt off
    repeat([1, 2, 3]).take(10)
                     .transparentDump("repeat")
                     .assertEqual([1, 2, 3, 1, 2, 3, 1, 2, 3, 1]);
    // dfmt on

    // dfmt off
    repeat([1, 2, 3], 3).transparentDump("repeat_times")
                        .assertEqual([1, 2, 3, 1, 2, 3, 1, 2, 3]);
    // dfmt on

    currentThreadScheduler.work();
}

Observable!TResult when(TResult, TSources...)(Plan!(TResult, TSources) plan)
{
    Disposable subscribe(Observer!TResult observer)
    {
        return plan.subscribe(observer);
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : transparentDump;

    assert(just(1).and(just(2), just(3)).then!int((a, b, c) => a + b + c).when()
            .transparentDump("AndThenWhen").wait() == 6);

    assert(range(0, 10).and(range(0, 20).skip(1)).and(range(0, 30).skip(2))
            .then!int((a, b, c) => a + b + c).when()
            .transparentDump("AndThenTen").length().wait() == 10);
}
