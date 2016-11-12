module reactived.observable.operators.transformations;

import std.functional;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import disposable = reactived.disposable;

/// Returns the first element in the source Observable sequence.
Observable!T first(T)(Observable!T source) pure @safe
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

/// Create an Observable sequence which maps input values to an output.
template map(alias fun)
{
    Observable!(typeof(unaryFun!(fun)(T.init))) map(T)(Observable!T observable)
    {
        Disposable subscribe(Observer!(typeof(unaryFun!(fun)(T.init))) observer)
        {
            void onNext(T value)
            {
                observer.onNext(unaryFun!(fun)(value));
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
