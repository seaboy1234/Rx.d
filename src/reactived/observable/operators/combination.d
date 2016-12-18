module reactived.observable.operators.combination;

import std.functional;
import core.sync.mutex;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
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

    range(0, 3).map!(x => range(1, x)).merge().sequenceEqual([1, 1, 2, 1, 2,
            3]).subscribe(v => assert(v));
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
