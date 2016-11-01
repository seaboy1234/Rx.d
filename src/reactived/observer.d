module reactived.observer;

import std.range : isInputRange, ElementType;

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

/// Informs the observer of a range of values.
template onNext(T, E) if (isInputRange!E && isObserver!(T, ElementType!(E)))
{
    void onNext(T observer, E values)
    {
        foreach (value; values)
        {
            observer.onNext(value);
        }
    }
}

unittest
{
    int calls;

    struct A
    {
        void onNext(int)
        {
            ++calls;
        }

        void onCompleted()
        {
        }

        void onError(Throwable)
        {
        }
    }

    auto observer = A();
    auto arr = [10, 20];

    onNext(observer, arr);

    assert(calls == arr.length);
}
