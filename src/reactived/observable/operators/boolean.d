module reactived.observable.operators.boolean;

import std.functional;
import reactived.observable;
import reactived.observer;
import reactived.disposable;
import disposable = reactived.disposable;

/// Creates an Observable which emits true if the source Observable has any elements or false otherwise.
Observable!bool any(T)(Observable!T source) pure @safe
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
    single(1).any().subscribe(value => assert(value, "value should be true."));

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
Observable!bool contains(T)(Observable!T source, T element)
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

/++
    Creates an Observable which is guaranteed to return at least one value.  
    If the source Observable is empty, returns the default value of T.
+/
Observable!T defaultIfEmpty(T)(Observable!T source)
{
    return defaultIfEmpty(source, T.init);
}

///
unittest
{
    int outVal = 1;
    empty!int().defaultIfEmpty().subscribe(value => assert(0 == (outVal = 0),
            "value should be 0"), () => assert(outVal == 0, "outVal should be 0."));
}

///
Observable!T defaultIfEmpty(T)(Observable!T source, T defaultValue)
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
    empty!int().defaultIfEmpty(10).subscribe(value => assert(value == 10, "value should be 0"));

    range(0, 5).defaultIfEmpty(10).all!(a => a != 10)
        .subscribe(value => assert(value, "value should be true."));
}