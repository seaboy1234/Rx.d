module reactived.observable.conversions;

import std.range.primitives;
import std.parallelism;

import core.sync.rwmutex;

import reactived.disposable : BooleanDisposable, Disposable, createDisposable;
import reactived.observable.types;
import reactived.observable.generators : create;
import reactived.observer;
import reactived.scheduler;
import reactived.util : LinkedQueue;

/// Create an Observable sequence using an InputRange.
Observable!(ElementType!Range) asObservable(Range)(Range input, Scheduler scheduler = taskScheduler) pure @safe nothrow 
        if (isInputRange!(Range))
{
    Disposable subscribe(Observer!(ElementType!Range) observer)
    {
        import reactived.scheduler : taskScheduler;

        BooleanDisposable subscription = new BooleanDisposable();

        scheduler.run((void delegate() self) {
            observer.onNext(input.front);

            input.popFront();

            if (!input.empty && !subscription.isDisposed)
            {
                self();
            }
            else
            {
                observer.onCompleted();
            }
        });

        return subscription;
    }

    return create(&subscribe);
}

///
unittest
{
    import std.concurrency : Generator, yield;
    import reactived.observable : take;
    import reactived.util : assertEqual, transparentDump;

    string[] arr = ["this", "is", "a", "sample", "range"];

    // dfmt off
    arr.asObservable()
       .transparentDump("range -> observable")
       .assertEqual(arr);
    // dfmt on

    auto r = new Generator!int({
        int count;
        while (true)
        {
            yield(count++);
        }
    });

    r.asObservable().take(10).assertEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
}

auto asTask(T)(Observable!T source, TaskPool pool = taskPool)
{
    static T getValue(Observable!T source)
    {
        bool completed;
        Throwable exception;
        T lastValue;

        void onNext(T value)
        {
            lastValue = value;
        }

        void onCompleted()
        {
            completed = true;
        }

        void onError(Throwable error)
        {
            exception = error;
            onCompleted();
        }

        source.observeOn(currentThreadScheduler).subscribe(&onNext, &onCompleted, &onError);

        while (!completed)
        {
            currentThreadScheduler.work();
        }

        if (exception !is null)
        {
            throw exception;
        }

        return lastValue;
    }

    auto t = task!getValue(source);

    pool.put(t);

    return t;
}

unittest
{
    import reactived.observable : map, timer, doOnNext;
    import reactived.util : transparentDump;
    import std.datetime : dur;
    import std.stdio : writeln;
    import std.string : format;

    auto t = timer(dur!"seconds"(1)).map!(v => 100).transparentDump("asTask").asTask();

    auto val = t.yieldForce();

    assert(val == 100, format("Expected 100.  Got %d.", val));
}

auto asRange(T)(Observable!T source) @trusted
{
    static class RangeObserver : Observer!T
    {
    @trusted:
        private
        {
            bool _completed;
            Throwable _error;
            LinkedQueue!T _values;
            Disposable _subscription;
            ReadWriteMutex _mutex;
        }

        this()
        {
            _values = new LinkedQueue!T();
            _subscription = createDisposable({  });
            _mutex = new ReadWriteMutex();
        }

        ~this()
        {
            _subscription.dispose();
        }

        @property
        {
            T front()
            {
                bool isEmpty;
                synchronized (_mutex.reader)
                {
                    isEmpty = _values.empty;
                }

                while (isEmpty)
                {
                    currentThreadScheduler.work();
                    synchronized (_mutex.reader)
                    {
                        if (_error !is null)
                        {
                            throw _error;
                        }
                        isEmpty = _values.empty;
                    }
                }

                synchronized (_mutex.writer)
                {
                    return _values.dequeue;
                }
            }

            bool empty()
            {
                synchronized (_mutex.reader)
                {
                    return _completed && _values.empty;
                }
            }

            Disposable subscription()
            {
                return _subscription;
            }

            void subscription(Disposable value)
            {
                _subscription.dispose();
                _subscription = value;
            }
        }

        void popFront()
        {

        }

        void onNext(T value)
        {
            synchronized (_mutex.writer)
            {
                _values.enqueue(value);
            }
        }

        void onCompleted()
        {
            synchronized (_mutex.writer)
            {
                _completed = true;
            }
        }

        void onError(Throwable error)
        {
            synchronized (_mutex.writer)
            {
                _error = error;
                _completed = true;
            }
        }
    }

    RangeObserver value = new RangeObserver();
    value.subscription = source.subscribe(value);
    value.popFront();

    return value;
}

unittest
{
    import reactived : range, map;
    import std.stdio : writeln;
    import std.math : sqrt;

    foreach (x; range(0, 10).map!(x => x ^^ 2).asRange())
    {
        writeln("asRange() => ", x);
    }
    writeln("asRange() => completed");
}

T wait(T)(Observable!T source)
{
    return source.asTask().yieldForce();
}
