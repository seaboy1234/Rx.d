module reactived.observable.operators.combination;

import disposable = reactived.disposable;
import reactived.disposable : createDisposable, Disposable, CompositeDisposable,
    RefCountDisposable;
import reactived.observable.generators : create;
import reactived.observable.types;
import reactived.observer;

/**
    Starts an observable sequence with the provided value, then emits values from the source observable.
*/
Observable!T startWith(T)(Observable!T source, T value)
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
