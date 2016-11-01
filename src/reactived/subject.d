module reactived.subject;

import reactived.observable;
import reactived.observer;
import reactived.disposable;
import reactived.util;
import std.exception : enforce;
import std.algorithm;

/// Represents a hybrid between an Observable and Observer, providing the functions of both.  
/// This will often be the root on an Observable sequence.
class Subject(T) : Observable!T, Observer!T
{
    private
    {
        bool _completed;
        List!(Observer!(T)) _observers;
    }

    /// Provides the next value to the underlying Observers.
    void onNext(T value)
    {
        if (_completed)
        {
            return;
        }

        try
        {
            foreach (observer; _observers)
            {
                observer.onNext(value);
            }
        }
        catch (Exception e)
        {
            onError(e);
        }
    }

    /// Causes the sequence to complete. 
    void onCompleted()
    {
        try
        {
            foreach (observer; _observers)
            {
                observer.onCompleted();
            }
        }
        catch (Exception e)
        {
            onError(e);
        }
        _observers.clear();
        _completed = true;
    }

    /// Causes the sequence to complete with the specified error.
    void onError(Throwable error)
    {
        _completed = true;

        foreach (observer; _observers)
        {
            observer.onError(error);
        }

        _observers.clear();
    }

    /// Subscribes an Observer to this Observable sequence.
    Disposable subscribe(Observer!(T) observer)
    {
        enforce(!_completed, "This Observable has already completed.");
        _observers.add(observer);

        return createDisposable(() => _observers.remove(observer));
    }
}

///
unittest
{
    import std.stdio : writeln;

    class MyObserver : Observer!(int)
    {
        void onNext(int value)
        {
            writeln(value);
        }

        void onCompleted()
        {
            writeln("Completed");
        }

        void onError(Throwable error)
        {
            writeln(error.msg);
        }
    }

    auto subject = new Subject!int();
    auto observer = new MyObserver();

    auto token = subject.subscribe(observer);

    subject.onNext(1); // => 1
    subject.onNext(2); // => 2
    token.dispose();
    subject.onNext(3); // (nothing)
}

/// Represents a Subject which is able to replay the values it receives.
class ReplaySubject(T) : Subject!(T)
{
    import std.datetime : Clock, SysTime, Duration;

    private
    {
        Duration _window;
        List!(SubjectItem) _items;
    }

    private struct SubjectItem
    {
        SysTime time;
        T item;
    }

    /// Instantiates the ReplaySubject with the max Duration.
    this()
    {
        this(Duration.max);
    }

    /// Instantiates the ReplaySubject with the specified window.
    this(Duration window)
    {
        _window = window;
    }

    override void onNext(T value)
    {
        _items.add(SubjectItem(Clock.currTime(), value));
        super.onNext(value);
    }

    override Disposable subscribe(Observer!T observer)
    {
        import std.algorithm : filter = filter;

        auto disposable = super.subscribe(observer);
        try
        {
            foreach (item; _items.range.filter!(g => g.time - Clock.currTime() <= _window))
            {
                observer.onNext(item.item);
            }

            foreach (item; _items.range.filter!(g => g.time - Clock.currTime() >= _window))
            {
                _items.remove(item);
            }
        }
        catch (Exception e)
        {
            onError(e);
        }
        return disposable;
    }
}

///
unittest
{
    import std.stdio : writeln;

    class MyObserver : Observer!(int)
    {
        void onNext(int value)
        {
            writeln(value);
        }

        void onCompleted()
        {
            writeln("Completed");
        }

        void onError(Throwable error)
        {
            writeln(error.msg);
        }
    }

    auto subject = new ReplaySubject!int();
    auto observer = new MyObserver();

    subject.onNext(1);
    auto token = subject.subscribe(observer);   // => 1
    subject.onNext(2);                          // => 2
    token.dispose();
    subject.onNext(3);

    subject.subscribe(observer);                // => 1
                                                // => 2
                                                // => 3
    subject.onCompleted();                      // => Completed
}

/// Masks the underlying source Observable.
Observable!T asObservable(T)(Observable!T source)
{
    Disposable subscribe(Observer!T observer)
    {
        return source.subscribe(observer);
    }

    return create(&subscribe);
}


/// 
unittest
{
    Subject!int subject = new Subject!int();

    auto masked = subject.asObservable();

    assert(typeid(typeof(masked)) != typeid(typeof(subject)), "");
}
