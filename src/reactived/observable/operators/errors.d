module reactived.observable.operators.errors;

import reactived.disposable : CompositeDisposable, Disposable;
import reactived.observable.types;
import reactived.observable.generators : create;
import reactived.observer;
import reactived.scheduler;

/**
    If source encounters an error, begin emitting notifications from next.
*/
Observable!T onErrorContinueWith(T)(Observable!T source, Observable!T next)
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
Observable!T onCompletedContinueWith(T)(Observable!T source, Observable!T next)
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
Observable!T continueWith(T)(Observable!T source, Observable!T next)
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

            subscription.add(source.subscribe(&observer.onNext, &observer.onCompleted, &onError_));

            return subscription;
        }

        return create(&subscribe);
    }
}

unittest
{
    import reactived : single, sequenceEqual;

    assert(create!int((Observer!int observer) {
        observer.onNext(1);
        observer.onNext(2);

        observer.onError(new Exception("Error123"));
        return delegate()
        {
        };
    }).catchException!Exception((Exception) {
        return single(3);
    }).sequenceEqual([1, 2, 3]), "Excepted true.  Got false.");   
}
