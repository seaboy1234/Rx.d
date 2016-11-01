module reactived.observable.types;

import reactived.observer;
import reactived.disposable : Disposable, createDisposable;

/// Represents an observable sequence of values.
interface Observable(T)
{
    /// Subscribe to the Observable using an Observer.
    Disposable subscribe(Observer!(T) observer);

    /// Subscribe to the Observable using onNext, onCompleted, and onError methods.
    final Disposable subscribe(void delegate(T value) onNext_,
            void delegate() onCompleted_, void delegate(Throwable) onError_)
    {
        class AnonymousObserver : Observer!T
        {
            private bool _completed;
            void onNext(T value)
            {
                if (_completed)
                {
                    return;
                }

                try
                {
                    onNext_(value);
                }
                catch (Exception e)
                {
                    onError(e);
                }
            }

            void onCompleted()
            {
                if (_completed)
                {
                    return;
                }
                _completed = true;
                onCompleted_();
            }

            void onError(Throwable error)
            {
                if (_completed)
                {
                    return;
                }

                onError_(error);
            }
        }

        return subscribe(new AnonymousObserver());
    }

    /// Subscribe to an Observable using an onNext method and empty stubs for onCompleted and onError.
    final Disposable subscribe(void delegate(T) onNext)
    {
        void onCompleted()
        {

        }

        void onError(Throwable)
        {

        }

        return subscribe(onNext, &onCompleted, &onError);
    }

    /// Subscribe to an Observable using onNext and onCompleted methods, leaving onError empty.
    final Disposable subscribe(void delegate(T) onNext, void delegate() onCompleted)
    {
        void onError(Throwable)
        {

        }

        return subscribe(onNext, onCompleted, &onError);
    }

    /// Subscribe to an Observable using onNext and onError methods, leaving onCompleted empty.
    final Disposable subscribe(void delegate(T) onNext, void delegate(Throwable) onError)
    {
        void onCompleted()
        {

        }

        return subscribe(onNext, &onCompleted, onError);
    }
}

/// Represents a value with no information.
struct Unit { }
