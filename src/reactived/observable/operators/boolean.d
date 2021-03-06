module reactived.observable.operators.boolean;

import std.functional;
import std.range.primitives;
import std.typecons;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import disposable = reactived.disposable;

/// Creates an Observable which emits true if the source Observable has any elements or false otherwise.
Observable!bool any(T)(Observable!T source) pure @safe nothrow
{
    Disposable subscribe(Observer!bool observer)
    {
        bool called;
        void onNext(T)
        {
            observer.onNext(called = true);
            observer.onCompleted();
        }

        void onCompleted()
        {
            observer.onNext(called);
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    just(1).any().subscribe(value => assert(value, "value should be true."));

    range(0, 10).any().subscribe(value => assert(value, "value should be true."));

    empty!int().any().subscribe(value => assert(!value, "value should be false."));
}

/++
    Generates an Observable which emits a single true value if any of the elements 
    in the underlying Observable satisfies `fun`; emits false otherwise.
+/
template any(alias fun)
{
    Observable!bool any(T)(Observable!T observable)
    {
        Disposable subscribe(Observer!bool observer)
        {
            bool called;
            void onNext(T value)
            {
                if (unaryFun!(fun)(value))
                {
                    observer.onNext(called = true);
                    observer.onCompleted();
                }
            }

            void onCompleted()
            {
                observer.onNext(called);
                observer.onCompleted();
            }

            return observable.subscribe(&onNext, &onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    range(0, 10).any!(a => a > 5).subscribe(value => assert(value, "value should be true."));

    range(0, 10).any!(a => a > 10).subscribe(value => assert(!value, "value should be false."));
}

/// Generates an Observable which emits true if fun is satisfied on all elements or false if fun at any point evaluates to false. 
template all(alias fun)
{
    Observable!bool all(T)(Observable!T observable)
    {
        Disposable subscribe(Observer!bool observer)
        {
            bool condition = true;
            void onNext(T value)
            {
                condition = unaryFun!(fun)(value);
                if (!condition)
                {
                    observer.onNext(condition);
                    observer.onCompleted();
                }
            }

            void onCompleted()
            {
                observer.onNext(condition);
                observer.onCompleted();
            }

            return observable.subscribe(&onNext, &onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

///
unittest
{
    import std.range.interfaces : inputRangeObject;

    range(0, 10).all!(a => a % 2 == 0).subscribe(value => assert(!value, "value should be false."));

    [0, 2, 4, 6, 8].asObservable().all!(a => a % 2 == 0)
        .subscribe(value => assert(value, "value should be true."));
}

/// Creates an Observable which emits true if element is contained within the source Observable.
Observable!bool contains(T)(Observable!T source, T element) pure @safe nothrow
{
    Disposable subscribe(Observer!bool observer)
    {
        void onNext(T value)
        {
            if (equalTo(element, value))
            {
                observer.onNext(true);
                observer.onCompleted();
            }
        }

        void onCompleted()
        {
            observer.onNext(false);
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

///
unittest
{
    range(0, 10).contains(7).subscribe(value => assert(value, "value should be true."));
    range(0, 10).contains(12).subscribe(value => assert(!value, "value should be false."));
}

/**
    Given one or more source Observables, emit events from whichever emits an event first.
*/
Observable!T amb(T)(Observable!T[] observables...) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        Observable!T selected;

        class AmbObserver : Observer!T
        {
            private Observable!T _observable;
            private Disposable _subscription;

            this(Observable!T observable)
            {
                _observable = observable;
                _subscription = observable.subscribe(this);
            }

            void onNext(T value)
            {
                if (pick())
                {
                    observer.onNext(value);
                }
            }

            void onError(Throwable e)
            {
                if (pick())
                {
                    observer.onError(e);
                }
            }

            void onCompleted()
            {
                if (pick())
                {
                    observer.onCompleted();
                }
            }

            bool pick()
            {
                synchronized
                {
                    if (selected is null)
                    {
                        selected = _observable;
                        return true;
                    }
                    else if (selected != _observable)
                    {
                        if (_subscription !is null)
                        {
                            _subscription.dispose();
                        }
                        return false;
                    }
                    return true;
                }
            }
        }

        CompositeDisposable subscription = new CompositeDisposable();
        foreach (observable; observables)
        {
            subscription.add(observable.subscribe(new AmbObserver(observable)));
        }

        return subscription;
    }

    return create(&subscribe);
}

///
unittest
{
    import std.datetime : dur;
    import std.stdio : writeln;

    string value;

    // dfmt off
    amb(
        timer(dur!"seconds"(1)).map!(v => "first"),
        timer(dur!"msecs"(100)).map!(v => "second"),
        timer(dur!"msecs"(1)).map!(v => "third")
    ).subscribe(v => assert("third" == (value = v)));
    // dfmt on

    while (value is null)
    {
    }

    writeln("amb() picked the ", value, " value");

    // => amb() picked the third value
}

/++
    Creates an Observable which is guaranteed to return at least one value.  
    If the source Observable is empty, returns the default value of T.
+/
Observable!T defaultIfEmpty(T)(Observable!T source) pure @safe nothrow
{
    return defaultIfEmpty(source, T.init);
}

///
unittest
{
    assert(empty!int().defaultIfEmpty().wait() == 0);
}

///
Observable!T defaultIfEmpty(T)(Observable!T source, T defaultValue) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        bool hasValue;
        void onNext(T value)
        {
            if (!hasValue)
            {
                hasValue = true;
            }
            observer.onNext(value);
        }

        void onCompleted()
        {
            if (!hasValue)
            {
                observer.onNext(defaultValue);
            }
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

unittest
{
    assert(empty!int().defaultIfEmpty(10).wait() == 10);

    assert(range(0, 5).defaultIfEmpty(10).all!(a => a != 10).wait());
}

Observable!bool sequenceEqual(T, Range)(Observable!T source, Range sequence) pure @safe nothrow 
        if (isInputRange!Range && is(T : ElementType!Range))
{
    Disposable subscribe(Observer!bool observer)
    {
        void onNext(T value)
        {
            if (sequence.empty || sequence.front != value)
            {
                observer.onNext(false);
                observer.onCompleted();
            }

            sequence.popFront();
        }

        void onCompleted()
        {
            if (sequence.empty)
            {
                observer.onNext(true);
            }
            else
            {
                observer.onNext(false);
            }
            observer.onCompleted();
        }

        return source.subscribe(&onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

unittest
{
    import reactived.util : assertEqual;

    range(0, 4).assertEqual([0, 1, 2, 3]);
    assert(!range(1, 4).sequenceEqual([0, 1, 2, 3]).wait());
    assert(!range(0, 0).sequenceEqual([9, 1091, 7]).wait());
    just(10).assertEqual([10]);
}

Observable!bool sequenceEqual(T)(Observable!T source, Observable!T other)
{
    static struct Union
    {
        T left;
        T right;
    }

    return source.zip!((left, right) => Union(left, right))(other).all!(x => x.left == x.right)();
}
