module reactived.observable.operators.transformations;

import std.functional;
import std.datetime;

import core.sync.rwmutex;
import core.sync.mutex;
import core.thread;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import reactived.scheduler;
import reactived.util : LinkedQueue;
import disposable = reactived.disposable;

/// Returns the first element in the source Observable sequence.
Observable!T first(T)(Observable!T source) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        Disposable subscription;
        bool called;
        void onNext(T value)
        {
            if (called)
            {
                if (subscription !is null)
                {
                    subscription.dispose();
                    subscription = null;
                }
                return;
            }
            called = true;
            observer.onNext(value);
            observer.onCompleted();
        }

        subscription = source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
        return subscription;
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    range(1, 10).first().subscribe(value => writeln("first() => ", value),
            () => writeln("first() => ", "completed"));

    /++
        Output

        first() => 1
        first() => completed
    +/
}

Observable!T last(T)(Observable!T source)
{
    Disposable subscribe(Observer!T observer)
    {
        T current;

        void onNext(T value)
        {
            current = value;
        }

        void onCompleted()
        {
            observer.onNext(current);
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : assertEqual;

    range(1, 10).last().assertEqual([10]);
}

Observable!T elementAt(T)(Observable!T source, size_t index)
in
{
    assert(index >= 0);
}
body
{
    Disposable subscribe(Observer!T observer)
    {
        BooleanDisposable subscription;

        void onNext(T value)
        {
            if (index-- == 0)
            {
                observer.onNext(value);
                observer.onCompleted();

                if (subscription !is null)
                {
                    subscription.dispose();
                }
            }
        }

        subscription = new BooleanDisposable(source.subscribe(&onNext,
                &observer.onCompleted, &observer.onError));

        return subscription;
    }

    return create(&subscribe);
}

/// Create an Observable sequence which maps input values to an output.
template map(alias fun)
{
    Observable!(typeof(unaryFun!(fun)(T.init))) map(T)(Observable!T observable)
    {
        Disposable subscribe(Observer!(typeof(unaryFun!(fun)(T.init))) observer)
        {
            void onNext(T value)
            {
                observer.onNext(unaryFun!fun(value));
            }

            return observable.subscribe(&onNext, &observer.onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    import std.stdio : writeln;
    import std.conv : to;

    range(0, 10).filter!(a => a % 2 == 0).map!(a => to!string(a))
        .subscribe(value => assert(typeid(typeof(value)) is typeid(string),
                "value should be string"));
}

template flatMap(alias fun)
{
    Observable!(typeof(unaryFun!fun(T.init)).ElementType) flatMap(T)(Observable!T source)
    {
        import reactived : merge;

        return source.map!fun().merge();
    }
}

unittest
{
    import reactived.util : assertEqual, dump;

    char toLetter(int value)
    {
        return cast(char)(value + 64);
    }

    range(1, 3).flatMap!(x => just(toLetter(x))).assertEqual(['A', 'B', 'C']);

    range(1, 3).flatMap!(x => range(1, x)).assertEqual([1, 1, 2, 1, 2, 3]);

    ["Hello,", "World!", "This", "is", "a", "test", "sentence"].asObservable(defaultScheduler)
        .flatMap!(x => x.asObservable(defaultScheduler)).dump("words");
}

/// Applies an accumulator function to all values in the source Observable and emits the current result with each value.
template scan(alias fun)
{
    Observable!T scan(T)(Observable!T source)
    {
        Disposable subscribe(Observer!T observer)
        {
            T currentValue;
            void onNext(T value)
            {
                currentValue = binaryFun!(fun)(currentValue, value);
                observer.onNext(currentValue);
            }

            void onCompleted()
            {
                observer.onCompleted();
            }

            return source.subscribe(&onNext, &onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

unittest
{
    import reactived.subject : Subject;

    auto s = new Subject!int();
    int value;

    s.scan!((a, b) => a + b).subscribe(delegate(x) { value = x; }, () => assert(value == 10));

    s.onNext(1);
    assert(value == 1);

    s.onNext(2);
    assert(value == 3);

    s.onNext(3);
    assert(value == 6);

    s.onNext(4);
    assert(value == 10);

    s.onCompleted();
}

Observable!(T[]) buffer(T)(Observable!T source, Duration window, size_t count = 0,
        Scheduler scheduler = taskScheduler) pure @safe nothrow
{
    Disposable subscribe(Observer!(T[]) observer)
    {
        BooleanDisposable subscription;
        T[] items;
        ReadWriteMutex mutex = new ReadWriteMutex();

        void flush()
        {
            synchronized (mutex.reader)
            {
                observer.onNext(items);
                items = T[].init;
            }
        }

        void onNext(T value)
        {
            synchronized (mutex.writer)
            {
                items ~= value;
            }

            synchronized (mutex.reader)
            {
                if (count > 0 && items.length > count)
                {
                    flush();
                }
            }
        }

        void onCompleted()
        {
            flush();
            observer.onCompleted();
        }

        void onError(Throwable e)
        {
            flush();
            observer.onError(e);
        }

        void run(void delegate() self)
        {
            import core.thread : Thread;

            Thread.sleep(window);

            flush();

            if (!subscription.isDisposed)
            {
                self();
            }
        }

        subscription = new BooleanDisposable(source.subscribe(&onNext, &onCompleted, &onError));

        scheduler.run(&run);

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    auto o = create((Observer!string observer) {
        import std.random : uniform;
        import std.range : iota;
        import core.thread : Thread;

        BooleanDisposable subscription = new BooleanDisposable();

        enum string[] MESSAGES = ["ABC", "DEF", "GHI", "JKL", "MNO", "PQR", "STU", "VWX", "YZA"];

        taskScheduler.run((self) {
            foreach (value; iota(0, uniform(1, 10)))
            {
                observer.onNext(MESSAGES[uniform(0, $)]);
            }

            Thread.sleep(dur!"msecs"(uniform(10, 250)));

            if (!subscription.isDisposed)
            {
                self();
            }
        });

        return subscription;
    });

    auto t = o.buffer(dur!"seconds"(1), 10).take(2).asTask();

    string[] vals = t.yieldForce();

    assert(vals.length > 0);
    assert(vals.length != 1);
}

Observable!(Observable!T) window(T)(Observable!T source, Duration size)
{
    Disposable subscribe(Observer!(Observable!T) observer)
    {
        import reactived : Subject;

        Subject!T current = new Subject!T();
        BooleanDisposable subscription = new BooleanDisposable();
        auto currentSubscription = assignmentDisposable();
        Mutex mutex = new Mutex();
        MonoTime windowOpened;
        bool completed, error;

        void onNext(T value)
        {
            auto duration = MonoTime.currTime - windowOpened;

            if (duration >= size)
            {
                windowOpened = MonoTime.currTime;

                current.onCompleted();
                current = new Subject!T();
                observer.onNext(current);
            }

            current.onNext(value);
        }

        void onCompleted()
        {
            completed = true;
            current.onCompleted();
            observer.onCompleted();
        }

        void onError(Throwable e)
        {
            error = true;
            observer.onError(e);
        }

        subscription = new BooleanDisposable(source.subscribe(&onNext, &onCompleted, &onError));

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import std.conv : to;
    import std.random : uniform;
    import std.typecons : tuple;
    import reactived.util : transparentDump, dump;

    int current;

    // dfmt off
    assert(range(0, 100).delay!(x => dur!"msecs"(uniform(1, 10)))
                        .window(dur!"msecs"(100))
                        .flatMap!(x => x.length())
                        .scan!((a, b) => a + b)
                        .transparentDump("Total items")
                        .wait() == 100);
    // dfmt on
}
