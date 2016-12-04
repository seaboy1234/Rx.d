module reactived.observable.conversions;

import std.range.primitives;
import std.parallelism;

import reactived.disposable : BooleanDisposable, Disposable;
import reactived.observable.types;
import reactived.observable.generators : create;
import reactived.observer;
import reactived.scheduler;

/// Create an Observable sequence using an InputRange.
Observable!(ElementType!Range) asObservable(Range)(Range input) pure @safe nothrow 
        if (isInputRange!(Range))
{
    Disposable subscribe(Observer!(ElementType!Range) observer)
    {
        import reactived.scheduler : taskScheduler;

        BooleanDisposable subscription = new BooleanDisposable();

        taskScheduler.run((void delegate() self) {
            observer.onNext(input.front);

            input.popFront();

            if (!input.empty && !subscription.isDisposed)
            {
                self();
            }
        });

        return subscription;
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;
    import std.concurrency : Generator, yield;
    import reactived.observable : take;

    string[] arr = ["this", "is", "a", "sample", "range"];

    arr.asObservable().observeOn(currentThreadScheduler)
        .subscribe(value => writeln(value), () => writeln("completed"));

    size_t index;
    arr.asObservable().observeOn(currentThreadScheduler).subscribe(v => assert(arr[index++] == v));

    auto r = new Generator!int({
        int count;
        while (true)
        {
            yield(count++);
        }
    });

    bool completed;
    r.asObservable().observeOn(currentThreadScheduler).take(10).subscribe(v => assert(v < 10), () {
        completed = true;
    });

    /++
        Output:

        this
        is
        a
        sample
        range
        completed
    +/

    currentThreadScheduler.work();

    assert(completed);
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
    import std.datetime : dur;
    import std.stdio : writeln;
    import std.string : format;

    auto t = timer(dur!"seconds"(1)).map!(v => 100).doOnNext((int v) {
        writeln("asTask(", v, ")");
    }).asTask();

    auto val = t.yieldForce();

    assert(val == 100, format("Expected 100.  Got %d.", val));
}

auto asRange(T)(Observable!T source)
{
    static struct RangeObserver
    {
        private Observable!T _source;

        this(Observable!T source)
        {
            _source = source;
        }

        int opApply(int delegate(ref T x) dg)
        {
            int completed = 0;

            //dfmt off
            BooleanDisposable subscription;

            subscription = new BooleanDisposable(_source.observeOn(currentThreadScheduler).subscribe(
            (v) {
                completed = dg(v);

                if (completed)
                {
                    subscription.dispose();
                }
            }, { 
                subscription.dispose(); 
            }, (e) { 
                subscription.dispose();
                throw e; 
            }));

            //dfmt on

            while (!subscription.isDisposed())
            {
                currentThreadScheduler.work();
            }

            return completed;
        }
    }

    return RangeObserver(source);
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
