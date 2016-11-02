module reactived.observable.filtering;

import reactived.observer;
import reactived.disposable : Disposable, createDisposable;
import reactived.observable;

import disposable = reactived.disposable;
import std.functional;
import std.traits;
import std.range.primitives;

/// Create an Observable sequence using the first n values from the source.
Observable!T take(T)(Observable!T source, int count) pure @safe
{
    Disposable subscribe(Observer!T observer)
    {
        int current;
        bool completed;

        void onNext(T value)
        {
            if (completed)
            {
                return;
            }

            if (current++ < count)
            {
                observer.onNext(value);
            }
            else
            {
                completed = true;
                observer.onCompleted();
            }
        }

        return source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).take(3).subscribe(value => writeln(value), () => writeln("completed"));

    /++
        Output:

        0
        1
        2
        completed
    +/
}

/// Create an Observable sequence which emits values while the condition is true.
template takeWhile(alias predicate = "a")
{
    Observable!T takeWhile(T)(Observable!T source) pure @safe
    {
        Disposable subscribe(Observer!T observer)
        {
            bool completed;

            void onNext(T value)
            {
                if (completed)
                {
                    return;
                }

                if (unaryFun!(predicate)(value))
                {
                    observer.onNext(value);
                }
                else
                {
                    observer.onCompleted();
                    completed = true;
                }
            }

            return source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).takeWhile!(g => g < 5).subscribe(value => writeln(value),
            () => writeln("completed"));

    /++
        Output:

        0
        1
        2
        3
        4
        5
        completed
    +/
}

/// Create an Observable sequence, skipping the first n elements.
Observable!T skip(T)(Observable!T observable, int count)
{
    Disposable subscribe(Observer!T observer)
    {
        int current;

        void onNext(T value)
        {
            if (current++ < count)
            {
                return;
            }
            observer.onNext(value);
        }

        return observable.subscribe(&onNext, &observer.onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).skip(2).subscribe(value => writeln(value), () => writeln("completed"));

    /++
        Output: 

        2
        3
        4
        ...
        7
        8
        9
        completed
    +/

}

/// Create an Observable sequence, skipping elements while the condition is met.
template skipWhile(alias predicate = "a")
{
    Observable!T skipWhile(T)(Observable!T source)
    {
        Disposable subscribe(Observer!T observer)
        {
            bool triggered;
            void onNext(T value)
            {
                if (!triggered)
                {
                    if (unaryFun!(predicate)(value))
                    {
                        return;
                    }
                    else
                    {
                        triggered = true;
                    }
                }
                observer.onNext(value);
            }

            return source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).skipWhile!(g => g < 5).subscribe(value => writeln(value),
            () => writeln("completed"));

    /++
        Output:

        5
        6
        7
        8
        9
        completed
    +/
}

/// Create an Observable sequence which returns all but the last n elements of the source sequence.
Observable!T skipLast(T)(Observable!T source, int count)
{
    Disposable subscribe(Observer!T observer)
    {
        T[] items;
        void onNext(T value)
        {
            items ~= value;
        }

        void onCompleted()
        {
            for (size_t i = 0; i < items.length - count; i++)
            {
                observer.onNext(items[i]);
            }
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).skipLast(1).subscribe(value => writeln("skipLast(1) => ",
            value), () => writeln("skipLast(1) => completed"));

    /++
        Output:

        skipLast(1) => 0
        skipLast(1) => 1
        ...
        skipLast(1) => 7
        skipLast(1) => 8
        skipLast(1) => completed
    +/

    range(0, 10).skipLast(5).subscribe(value => writeln("skipLast(5) => ",
            value), () => writeln("skipLast(5) => completed"));

    /++
        Output:

        skipLast(5) => 0
        skipLast(5) => 1
        skipLast(5) => 2
        skipLast(5) => 3
        skipLast(5) => 4
        skipLast(5) => completed
    +/
}

/// Create an Observable sequence which returns only the last n elements of the source sequence.
Observable!T takeLast(T)(Observable!T source, int count)
{
    Disposable subscribe(Observer!T observer)
    {
        T[] items = [];
        items.length = count;

        int current;

        void onNext(T value)
        {
            items[current++ % count] = value;
        }

        void onCompleted()
        {
            for (size_t i = current; i < count + current; i++)
            {
                observer.onNext(items[i % count]);
            }
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;

    range(0, 10).takeLast(1).subscribe(value => writeln("takeLast(1) => ",
            value), () => writeln("takeLast(1) => completed"));

    range(0, 10).takeLast(5).subscribe(value => writeln("takeLast(5) => ",
            value), () => writeln("takeLast(5) => completed"));
}

/// Create an Observable sequence which emits only unique values from the source.
Observable!T distinct(T)(Observable!T source)
{
    Disposable subscribe(Observer!T observer)
    {
        size_t[] hashCodes = [];

        void onNext(T value)
        {
            import std.algorithm : canFind;

            auto hash = typeid(T).getHash(&value);
            if (!hashCodes.canFind(hash))
            {
                hashCodes ~= hash;
                observer.onNext(value);
            }
        }

        return source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

/// Create an Observable sequence which emits elements different from the previous.
Observable!T distinctUntilChanged(T)(Observable!T source)
{
    Disposable subscribe(Observer!T observer)
    {
        size_t last;
        void onNext(T value)
        {
            immutable auto hash = typeid(T).getHash(&value);
            if (last != hash)
            {
                last = hash;
                observer.onNext(value);
            }

        }

        return source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    import std.stdio : writeln;
    import reactived.subject : Subject;

    Subject!int subject = new Subject!int();

    subject.distinct().subscribe(value => writeln("distinct(", value, ")"),
            () => writeln("completed"));
    subject.distinctUntilChanged().subscribe(value => writeln("distinctUntilChanged(",
            value, ")"), () => writeln("distinctUntilChanged completed"));

    writeln("distinct test");

    writeln("subject.onNext(", 1, ")");
    subject.onNext(1);

    writeln("subject.onNext(", 1, ")");
    subject.onNext(1);

    writeln("subject.onNext(", 2, ")");
    subject.onNext(2);

    writeln("subject.onNext(", 1, ")");
    subject.onNext(1);

    writeln("subject.onNext(", 3, ")");
    subject.onNext(3);

    subject.onCompleted();
}

/// Create an Observable which filters elements not conforming to the predicate.
template filter(alias predicate = "a")
{
    Observable!T filter(T)(Observable!T observable)
    {
        Disposable subscribe(Observer!T observer)
        {
            void onNext(T value)
            {
                if (unaryFun!(predicate)(value))
                {
                    observer.onNext(value);
                }
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

    range(0, 10).filter!(a => a % 2 == 0).subscribe(value => assert(value % 2 == 0,
            "value should be even."));

    int[] values;

    range(0, 100).filter!(a => a % 3 == 0).filter!(a => a % 5 == 0).subscribe(delegate(value) {
        values ~= value;
    }, () => assert(values == [0, 15, 30, 45, 60, 75, 90], "Composing filters"));
}

/**
    Divides a source Observable into a series of Observables which emit a subset of the source.

    Calls to the keySelector function are modeled by the following equation:
    <em>calls = (<strong>[spawned observables]</strong> + 1) * <strong>[total elements]</strong></em>
*/
template groupBy(alias keySelector)
{
    alias getKey = unaryFun!(keySelector);

    Observable!(GroupedObservable!(typeof(getKey(TValue.init)), TValue)) groupBy(TValue)(
            Observable!TValue source)
    {
        alias TKey = typeof(getKey(TValue.init));

        class AnonymousGroupedObservable : GroupedObservable!(TKey, TValue)
        {
            private TKey _key;

            Observable!TValue _source;

            this(Observable!TValue source, TKey key) pure
            {
                _source = source;
                _key = key;
            }

            TKey key() @property
            {
                return _key;
            }

            Disposable subscribe(Observer!TValue observer)
            {
                return _source.subscribe(observer);
            }
        }

        Disposable subscribe(Observer!(GroupedObservable!(TKey, TValue)) observer)
        {
            GroupedObservable!(TKey, TValue)[TKey] observables;
            void onNext(TValue value)
            {
                TKey key = getKey(value);
                if (key !in observables)
                {
                    auto observable = source.filter!(a => key == getKey(a));
                    observables[key] = new AnonymousGroupedObservable(observable, key);
                    observer.onNext(observables[key]);
                }
            }

            return source.subscribe(&onNext, &observer.onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    int observables;

    // Create 10 lots of 10.

    int modulate(int value)
    {
        return value % 10;
    }

    range(0, 100).groupBy!(modulate).subscribe(delegate(observable) {
        ++observables;
        int values;
        observable.subscribe(delegate(int) { ++values; }, delegate() {
            assert(values == 10);
        });
    });

    assert(observables == 10);
}
