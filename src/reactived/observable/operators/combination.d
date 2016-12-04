module reactived.observable.operators.combination;

import disposable = reactived.disposable;
import reactived.disposable : createDisposable, Disposable, CompositeDisposable,
    RefCountDisposable, AssignmentDisposable;
import reactived.observable.generators : create;
import reactived.observable.types;
import reactived.observer;

/**
    Starts an observable sequence with the provided value, then emits values from the source observable.
*/
Observable!T startWith(T)(Observable!T source, T value) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        observer.onNext(value);
        return source.subscribe(observer);
    }

    return create(&subscribe);
}

template startWith(Range) if (isRange!(Range) && is(ElementType!Range : T))
{
    Observable!T startWith(T)(Observable!T source, Range range)
    {
        Disposable subscribe(Observer!T observer)
        {
            foreach (value; range)
            {
                observer.onNext(value);
            }
            return source.subscribe(observer);
        }

        return create(&subscribe);
    }
}

unittest
{
    import reactived.subject : Subject;
    import reactived.observable.operators.boolean : sequenceEqual;

    auto s = new Subject!int();

    s.onNext(1);
    s.onNext(2);
    s.onNext(3);

    auto o = s.startWith(0);

    o.sequenceEqual([0, 1, 2, 3]).subscribe(v => assert(v));
}

Observable!T endWith(T)(Observable!T source, T value) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        void onCompleted()
        {
            observer.onNext(value);
            observer.onCompleted();
        }

        return source.subscribe(&observer.onNext, &onCompleted, &observer.onError);
    }

    return create(&subscribe);
}

template endWith(Range) if (isRange!(Range) && is(ElementType!Range : T))
{
    Observable!T endWith(T)(Observable!T source, Range range)
    {
        Disposable subscribe(Observer!T observer)
        {
            void onCompleted()
            {
                foreach (value; range)
                {
                    observer.onNext(value);
                }
            }

            return source.subscribe(&observer.onNext, &onCompleted, &observer.onError);
        }

        return create(&subscribe);
    }
}

unittest
{
    import reactived.subject : Subject;
    import reactived.observable.operators.boolean : sequenceEqual;

    auto s = new Subject!int();

    s.onNext(1);
    s.onNext(2);
    s.onNext(3);

    auto o = s.endWith(4);

    o.sequenceEqual([1, 2, 3, 4]).subscribe(v => assert(v));
}

Observable!T latest(T)(Observable!(Observable!T) source) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        AssignmentDisposable assignment = new AssignmentDisposable();
        Disposable subscription;

        void onCompleted()
        {
            subscription.dispose();
            observer.onCompleted();
        }

        void onNext(Observable!T value)
        {
            assignment.disposable = value.subscribe(&observer.onNext, &onCompleted, &observer.onError);
        }

        subscription = source.subscribe(&onNext, &onCompleted, &observer.onError);

        return new CompositeDisposable(subscription, assignment);
    }

    return create(&subscribe);
}

unittest
{
    import reactived : range, map, sequenceEqual;

    assert(range(0, 5).map!(x => range(0, x)).latest().sequenceEqual([0, 1, 2, 3, 4]));
}
