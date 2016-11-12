module reactived.observable.operators.aggregate;

import std.functional;
import reactived.observable;
import reactived.observer;
import reactived.disposable;
import disposable = reactived.disposable;

/// Create an Observable using an accumulator function.
template reduce(alias fun)
{
    Observable!T reduce(T)(Observable!T source)
    {
        Disposable subscribe(Observer!T observer)
        {
            T currentValue;
            void onNext(T value)
            {
                currentValue = binaryFun!(fun)(currentValue, value);
            }

            void onCompleted()
            {
                observer.onNext(currentValue);
                observer.onCompleted();
            }

            return source.subscribe(&onNext, &onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).reduce!((a, b) => a + b).subscribe(value => assert(value == 45,
            "Sum of 1..10 is 45."));
}

/// Create an Observable which returns the length of the source observable.
Observable!size_t length(T)(Observable!T source)
{
    Disposable subscribe(Observer!size_t observer)
    {
        size_t length;
        void onNext(T)
        {
            ++length;
        }

        void onCompleted()
        {
            observer.onNext(length);
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    range(0, 10).length().subscribe(value => assert(value == 10, "value should be 10"));
}
