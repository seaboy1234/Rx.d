module reactived.observable.conversions;

import std.range.primitives;

import reactived.disposable : BooleanDisposable, Disposable;
import reactived.observable.types;
import reactived.observable.generators : create;
import reactived.observer;
import reactived.scheduler;

/// Create an Observable sequence using an InputRange.
Observable!(ElementType!Range) asObservable(Range)(Range input) pure @safe if (isInputRange!(Range))
{
    Disposable subscribe(Observer!(ElementType!Range) observer)
    {
        import reactived.scheduler : taskScheduler;
        BooleanDisposable subscription = new BooleanDisposable();

        taskScheduler.run((void delegate() self) {
            input.popFront();

            observer.onNext(input.front);

            if(!input.empty && !subscription.isDisposed)
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