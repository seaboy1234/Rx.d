module reactived.observable.operators.combination;

import std.functional;
import core.sync.mutex;

import reactived;
import reactived.util : LinkedQueue;
import disposable = reactived.disposable;

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
    import reactived.util : assertEqual;

    range(1, 3).startWith(0).assertEqual([0, 1, 2, 3]);
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
    import reactived.util : assertEqual;

    range(1, 3).endWith(4).assertEqual([1, 2, 3, 4]);
}

alias latest = switchLatest;

Observable!T merge(T)(Observable!(Observable!T) source) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        CompositeDisposable subscription = new CompositeDisposable();

        void onNext(Observable!T value)
        {
            subscription.add(value.subscribe(&observer.onNext, &observer.onError));
        }

        subscription ~= source.subscribe(&onNext, &observer.onCompleted, &observer.onError);

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import reactived : range, map, sequenceEqual;
    import reactived.util : transparentDump, assertEqual;

    // dfmt off
    range(1, 3).map!(x => range(1, x))
               .merge()
               .transparentDump("merge")
               .assertEqual([1, 1, 2, 1, 2, 3]);
    // dfmt on
}

template combineLatest(alias fun)
{
    Observable!(typeof(binaryFun!fun(L.init, R.init))) combineLatest(L, R)(
            Observable!L source, Observable!R other)
    {
        alias select = binaryFun!fun;
        alias ReturnType = typeof(select(L.init, R.init));

        Disposable subscribe(Observer!ReturnType observer)
        {
            CompositeDisposable subscription = new CompositeDisposable();

            bool startLeft, startRight, endedLeft, endedRight;

            L currentLeft;
            R currentRight;

            void onNext()
            {
                if (startLeft && startRight)
                {
                    observer.onNext(select(currentLeft, currentRight));
                }
            }

            void onNextLeft(L left)
            {
                startLeft = true;
                currentLeft = left;
                onNext();
            }

            void onNextRight(R right)
            {
                startRight = true;
                currentRight = right;
                onNext();
            }

            void onCompleted()
            {
                if (endedLeft && endedRight)
                {
                    observer.onCompleted();
                }
            }

            void onCompletedLeft()
            {
                endedLeft = true;
                onCompleted();
            }

            void onCompletedRight()
            {
                endedRight = true;
                onCompleted();
            }

            void onError(Throwable error)
            {
                subscription.dispose();
                observer.onError(error);
            }

            subscription ~= source.subscribe(&onNextLeft, &onCompletedLeft, &onError);
            subscription ~= other.subscribe(&onNextRight, &onCompletedRight, &onError);

            return subscription;
        }

        return create(&subscribe);
    }
}

unittest
{
    import std.conv : to;
    import reactived : Subject, sequenceEqual;

    Subject!char left = new Subject!char();
    Subject!int right = new Subject!int();

    // dfmt off
    Disposable combined = left.combineLatest!((x, y) => to!string(x) ~ to!string(y))(right)
                              .sequenceEqual(["A1", "B1", "C1", "C2", "C3", "C4", "C5", "D5", "E5", "E6"])
                              .subscribe(x => assert(x));
    // dfmt on

    left.onNext('A');
    right.onNext(1);

    left.onNext('B');
    left.onNext('C');
    right.onNext(2);
    right.onNext(3);

    right.onNext(4);
    right.onNext(5);
    left.onNext('D');
    left.onNext('E');

    left.onCompleted();

    right.onNext(6);
    right.onCompleted();

    combined.dispose();
}

template zip(alias fun)
{
    Observable!(typeof(binaryFun!fun(L.init, R.init))) zip(L, R)(Observable!L source,
            Observable!R other)
    {
        alias select = binaryFun!fun;
        alias ReturnType = typeof(select(L.init, R.init));
        Disposable subscribe(Observer!ReturnType observer)
        {
            CompositeDisposable subscription = new CompositeDisposable();
            Mutex mutex = new Mutex();

            LinkedQueue!L leftQueue = new LinkedQueue!L();
            LinkedQueue!R rightQueue = new LinkedQueue!R();

            void onNextLeft(L left)
            {
                synchronized (mutex)
                {
                    if (rightQueue.empty)
                    {
                        leftQueue.enqueue(left);
                    }
                    else
                    {
                        R right = rightQueue.dequeue;
                        ReturnType result = select(left, right);
                        observer.onNext(result);
                    }
                }
            }

            void onNextRight(R right)
            {
                synchronized (mutex)
                {
                    if (leftQueue.empty)
                    {
                        rightQueue.enqueue(right);
                    }
                    else
                    {
                        L left = leftQueue.dequeue;
                        ReturnType result = select(left, right);
                        observer.onNext(result);
                    }
                }
            }

            void onCompleted()
            {
                subscription.dispose();
                observer.onCompleted();
            }

            void onError(Throwable error)
            {
                subscription.dispose();
                observer.onError(error);
            }

            subscription ~= source.subscribe(&onNextLeft, &onCompleted, &onError);
            subscription ~= other.subscribe(&onNextRight, &onCompleted, &onError);

            return subscription;
        }

        return create(&subscribe);
    }
}

unittest
{
    import std.conv : to;
    import reactived : Subject, sequenceEqual;

    Subject!char left = new Subject!char();
    Subject!int right = new Subject!int();

    // dfmt off
    Disposable zipped = left.zip!((x, y) => to!string(x) ~ to!string(y))(right)
                            .sequenceEqual(["A1", "B2", "C3", "D4", "E5"])
                            .subscribe(x => assert(x));
    // dfmt on

    left.onNext('A');
    right.onNext(1);

    left.onNext('B');
    left.onNext('C');
    right.onNext(2);
    right.onNext(3);

    right.onNext(4);
    right.onNext(5);
    left.onNext('D');
    left.onNext('E');

    left.onCompleted();
    right.onCompleted();

    zipped.dispose();
}

Observable!T switchLatest(T)(Observable!(Observable!T) source)
{
    Disposable subscribe(Observer!T observer)
    {
        CompositeDisposable subscription = new CompositeDisposable();

        auto current = assignmentDisposable();

        void onCompleted()
        {
            subscription.dispose();
            observer.onCompleted();
        }

        void onError(Throwable error)
        {
            current.dispose();
            observer.onError(error);
        }

        void onNext(Observable!T next)
        {
            current = next.subscribe(&observer.onNext, &onCompleted, &onError);
        }

        subscription ~= current;
        subscription ~= source.subscribe(&onNext, &onError);

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import reactived : Subject;
    import reactived.util : transparentDump;

    Subject!(Observable!int) subject = new Subject!(Observable!int);

    Subject!(int)[3] subjects = [new Subject!int(), new Subject!int(), new Subject!int()];

    // dfmt off
    auto sub = subject.switchLatest()
                      .transparentDump("switchLatest")
                      .sequenceEqual([1, 2, 3, 4, 5])
                      .subscribe(x => assert(x));
    // dfmt on

    subject.onNext(subjects[0]);
    subjects[0].onNext(1);
    subjects[0].onNext(2);
    subject.onNext(subjects[1]);
    subjects[1].onNext(3);
    subjects[0].onNext(1);
    subject.onNext(subjects[0]);
    subjects[0].onNext(4);
    subjects[1].onNext(4);
    subject.onNext(subjects[2]);
    subjects[2].onNext(5);

    subjects[2].onCompleted();

    subject.onCompleted();
}

Observable!T concat(T)(Observable!(Observable!T) sources...)
{
    Disposable subscribe(Observer!T observer)
    {
        auto subscription = assignmentDisposable();
        CompositeDisposable composite = new CompositeDisposable(subscription);
        LinkedQueue!(Observable!T) observables = new LinkedQueue!(Observable!T);
        bool completed, waiting;

        void onError(Throwable e)
        {
            composite.dispose();
            observer.onError(e);
        }

        void onCompleted()
        {
            if (completed && observables.empty)
            {
                subscription.dispose();
                observer.onCompleted();
                return;
            }
            else if (observables.empty)
            {
                waiting = true;
                return;
            }

            subscription = observables.dequeue.subscribe(&observer.onNext,
                    &onCompleted, &onError);
        }

        void onNext(Observable!T value)
        {
            observables.enqueue(value);
            if (waiting)
            {
                onCompleted();
            }
        }

        void onSourcesCompleted()
        {
            if (waiting)
            {
                observer.onCompleted();
            }
            completed = true;
        }

        waiting = true;

        composite ~= sources.subscribe(&onNext, &onSourcesCompleted, &onError);

        return subscription;
    }

    return create(&subscribe);
}

Observable!(T[0].ElementType) concat(T...)(T sources) if (T.length > 1)
{
    T[0][] items;

    foreach (i, value; sources)
    {
        static if (!is(T[i] == T[0]))
        {
            static assert(0, T[i].mangleof ~ "is not a " ~ T[0].mangleof ~ "!");
        }
        items ~= value;
    }

    return concat(items.asObservable());
}

unittest
{
    import reactived.util : assertEqual, transparentDump;

    just(1).concat(just(2), just(3)).transparentDump("concat").assertEqual([1, 2, 3]);

    assert(!is(typeof({ concat(just(1), just("1")); })));
}
