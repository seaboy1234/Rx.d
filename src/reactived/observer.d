module reactived.observer;

/// Represents an Observer which listens on an Observable sequence.
interface Observer(T)
{
    /// Invoked when the next value in the Observable sequence is available.
    void onNext(T value);

    /// Invoked when the Observable sequence terminates due to an error.
    void onError(Throwable error);

    /// Invoked when the Observable sequence terminates successfully.
    void onCompleted();
}

template isObserver(T, E)
{
    enum bool isObserver = __traits(compiles, {
        T observer = void;
        E element = void;

        observer.onNext(element);
        observer.onError(Throwable.init);
        observer.onCompleted();
    });
}

unittest
{
    struct A
    {
        void onNext(int)
        {
        }

        void onCompleted()
        {
        }

        void onError(Throwable)
        {
        }
    }

    struct B
    {
        int onNext(int)
        {
            return 1;
        }

        void onCompleted()
        {
        }

        void onError(Throwable)
        {
        }
    }

    struct C
    {
        void next(int)
        {

        }

        void completed()
        {
        }

        void error(Throwable)
        {
        }
    }

    assert(isObserver!(Observer!(int), int));
    assert(isObserver!(A, int));
    assert(isObserver!(B, int));
    assert(!isObserver!(C, int));
}
