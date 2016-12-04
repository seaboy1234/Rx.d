module reactived.observable.operators.errors;

import reactived.disposable : AssignmentDisposable, CompositeDisposable,
    Disposable;
import reactived.observable.types;
import reactived.observable.generators : create;
import reactived.observer;
import reactived.scheduler;

/**
    If source encounters an error, begin emitting notifications from next.
*/
Observable!T onErrorContinueWith(T)(Observable!T source, Observable!T next) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        CompositeDisposable subscription = new CompositeDisposable();

        void onError(Throwable)
        {
            subscription.add(next.subscribe(observer));
        }

        subscription.add(source.subscribe(&observer.onNext, &observer.onCompleted, &onError));

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import reactived.subject : Subject, ReplaySubject;
    import reactived.util : dump;

    Subject!int x = new Subject!int();
    Subject!int y = new ReplaySubject!int();

    auto sub = x.onErrorContinueWith(y).dump("x.onErrorContinueWith(y)");

    x.onNext(1);
    x.onNext(2);
    y.onNext(3); // call to y; ignored until switch-over.
    x.onNext(4);

    x.onError(new Exception("Oh no!"));

    y.onNext(5);
}

/**
    When source completes, begin emitting notifications from next.
*/
Observable!T onCompletedContinueWith(T)(Observable!T source, Observable!T next) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        CompositeDisposable subscription = new CompositeDisposable();

        void onCompleted()
        {
            subscription.add(next.subscribe(observer));
        }

        subscription.add(source.subscribe(&observer.onNext, &onCompleted, &observer.onError));

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import reactived.subject : Subject, ReplaySubject;
    import reactived.util : dump;

    Subject!int x = new ReplaySubject!int();
    Subject!int y = new ReplaySubject!int();

    auto sub = x.onCompletedContinueWith(y).dump("x.onCompletedContinueWith(y)");

    x.onNext(1);
    x.onNext(2);
    y.onNext(3); // call to y; ignored until switch-over.
    x.onNext(4);
    y.onNext(5);

    x.onCompleted();
    y.onCompleted();
}

/**
    If source encounters an error or completes, begin emitting notifications from next.
*/
Observable!T continueWith(T)(Observable!T source, Observable!T next) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        CompositeDisposable subscription = new CompositeDisposable();

        void onCompleted()
        {
            subscription.add(next.subscribe(observer));
        }

        void onError(Throwable)
        {
            subscription.add(next.subscribe(observer));
        }

        subscription.add(source.subscribe(&observer.onNext, &onCompleted, &onError));

        return subscription;
    }

    return create(&subscribe);
}

template catchException(TException) if (is(TException : Exception))
{
    Observable!T catchException(T)(Observable!T source, Observable!T delegate(TException) onError)
    {
        Disposable subscribe(Observer!T observer)
        {
            CompositeDisposable subscription = new CompositeDisposable();

            void onError_(Throwable e)
            {
                if (auto ex = cast(TException) e)
                {
                    subscription.add(onError(ex).subscribe(observer));
                }
            }

            subscription.add(source.subscribe(&observer.onNext,
                    &observer.onCompleted, &onError_));

            return subscription;
        }

        return create(&subscribe);
    }
}

unittest
{
    import reactived : single, sequenceEqual;

    // dfmt off
    create!int((Observer!int observer) {
            observer.onNext(1);
            observer.onNext(2);

            observer.onError(new Exception("Error123"));
            return delegate()
            {
            };
        }).catchException!Exception((Exception) {
            return single(3);
        }).sequenceEqual([1, 2, 3]).subscribe(x => assert(x, "Excepted true.  Got false.")); 
        //dfmt on
}

Observable!T retry(T)(Observable!T source) pure @safe nothrow
{
    return source.retry(-1);
}

Observable!T retry(T)(Observable!T source, size_t retryCount) pure @safe nothrow
{
    Disposable subscribe(Observer!T observer)
    {
        AssignmentDisposable subscription = new AssignmentDisposable();
        void onError(Throwable e)
        {
            import std.stdio : writeln;
            writeln("threw");
            if (--retryCount != 0)
            {
                subscription.disposable = source.subscribe(&observer.onNext,
                        &observer.onCompleted, &onError);
            }
            else
            {
                observer.onError(e);
            }
        }

        subscription.disposable = source.subscribe(&observer.onNext,
                &observer.onCompleted, &onError);

        return subscription;
    }

    return create(&subscribe);
}

unittest
{
    import std.exception : assertNotThrown;
    import std.random : Random, unpredictableSeed;
    import reactived.disposable : empty;
    import reactived.observable.conversions : asTask;

    int autoThrow = 11;
    bool threw;

    void randomThrow()
    {
        auto rng = Random(unpredictableSeed);
        if (rng.front() % 10 == 1 || --autoThrow == 0)
        {
            threw = true;
            autoThrow = 11;
            throw new Exception("FAILED");
        }
    }

    Disposable subscribe(Observer!int observer)
    {
        for (int i = 0; i < 10; i++)
        {
            randomThrow();
            observer.onNext(i);
        }
        observer.onCompleted();

        return empty();
    }

    auto o = create(&subscribe).retry();

    assertNotThrown(o.asTask().yieldForce());
}
