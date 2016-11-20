module reactived.observable.conversions;

import std.range.primitives;

import reactived.disposable : BooleanDisposable, Disposable;
import reactived.observable.types;
import reactived.observable.generators : create;
import reactived.observer;
import reactived.scheduler;

/// Create an Observable sequence using an InputRange.
Observable!(ElementType!Range) asObservable(Range)(Range input) pure @safe 
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
