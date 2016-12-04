module reactived.observable.operators.aggregate;

import std.functional;
import std.traits;
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
Observable!size_t length(T)(Observable!T source) pure @safe nothrow
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

Observable!T max(T)(Observable!T source) pure @safe nothrow if (isNumeric!T)
{
    Disposable subscribe(Observer!T observer)
    {
        static if (isIntegral!T)
        {
            T max;
        }
        else static if (isFloatingPoint!T)
        {
            // Floating points are initialized to NaN.
            T max = 0;
        }
        else
        {
            static assert(0);
        }

        void onNext(T value)
        {
            if (value > max)
            {
                max = value;
            }
        }

        void onCompleted()
        {
            observer.onNext(max);
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

unittest
{
    import reactived.subject : Subject;

    void test(T...)(T args) if (T.length > 1 && isNumeric!(T[0]))
    {
        static import std.algorithm;
        import std.string : format;

        alias K = T[0];
        alias O = Observable!K;

        Subject!K s = new Subject!K();
        O o = s.max();

        K expected = std.algorithm.max(args);
        K actual;

        o.subscribe((v) { actual = v; });

        foreach (val; args)
        {
            s.onNext(val);
        }

        s.onCompleted();

        assert(expected == actual, format("Expected ", expected, ".  Got ", actual));
    }

    test(1, 2, 5, 8, 9, 1);
    test(2f, 3, 4, 8, 1, 0);
    test(1, 1, 1, 1, 1, 1);
    test(10, 0);
}

Observable!T min(T)(Observable!T source) pure @safe nothrow if (isNumeric!T)
{
    Disposable subscribe(Observer!T observer)
    {

        T min = T.max;

        void onNext(T value)
        {
            if (value < min)
            {
                min = value;
            }
        }

        void onCompleted()
        {
            observer.onNext(min);
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

unittest
{
    import reactived.subject : Subject;

    void test(T...)(T args) if (T.length > 1 && isNumeric!(T[0]))
    {
        static import std.algorithm;
        import std.string : format;

        alias K = T[0];
        alias O = Observable!K;

        Subject!K s = new Subject!K();
        O o = s.min();

        K expected = std.algorithm.min(args);
        K actual;

        o.subscribe((v) { actual = v; });

        foreach (val; args)
        {
            s.onNext(val);
        }

        s.onCompleted();

        assert(expected == actual, format("Expected %d. Got %d.", expected, actual));
    }

    test(1, 2, 5, 8, 9, 1);
    test(2f, 3, 4, 8, 1, 0);
    test(1, 1, 1, 1, 1, 1);
    test(10, 0);
}
