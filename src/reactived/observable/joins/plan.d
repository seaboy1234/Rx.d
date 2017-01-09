module reactived.observable.joins.plan;

import std.algorithm;
import std.typecons;
import std.meta;

import reactived;
import reactived.subject;
import reactived.util : LinkedQueue;

class Plan(TResult, TSources...)
{
    alias TElements = ElementTypes!TSources;
    alias Queues = QueueTypes!(TElements);

    private Subject!TResult _subject;

    private Queues _queues;

    private Pattern!TSources _pattern;
    private TResult delegate(TElements) _selector;

    private CompositeDisposable _subscriptions;

    private bool[TSources.length] _completed;
    private bool _active;

    this(Pattern!(TSources) pattern, TResult delegate(TElements) selector)
    {
        _pattern = pattern;
        _selector = selector;

        _subject = new Subject!TResult();
        _subscriptions = new CompositeDisposable();

        foreach (i, ref queue; _queues)
        {
            queue = new LinkedQueue!(TElements[i]);
        }
    }

package(reactived):
    Disposable subscribe(Observer!TResult observer)
    {
        Disposable subscription = _subject.subscribe(observer);
        if (!_active)
        {
            activate();
        }
        return subscription;
    }

private:

    void activate()
    {
        _active = true;
        foreach (i, value; _pattern)
        {
            createObserver(value, _queues[i], _completed[i]);
        }
    }

    void match()
    {
        if (!anyEmpty)
        {
            Tuple!(TElements) values;

            foreach (i, queue; _queues)
            {
                values[i] = queue.dequeue;
            }

            TResult value = _selector(values.tupleof);
            _subject.onNext(value);
        }
    }

    Observer!TSource createObserver(TSource)(Observable!TSource source,
            LinkedQueue!TSource queue, ref bool completed)
    {
        class JoinObserver : ObserverBase!TSource
        {
            override void onNextCore(TSource value)
            {
                queue.enqueue(value);
                match();
            }

            override void onCompletedCore()
            {
                completed = true;

                if (_completed[].all())
                {
                    _subscriptions.dispose();
                    _subject.onCompleted();
                }
            }

            override void onErrorCore(Throwable error)
            {
                scope (exit)
                {
                    _subscriptions.dispose();
                }
                _subject.onError(error);
            }
        }

        auto observer = new JoinObserver();

        _subscriptions ~= source.subscribe(observer);

        return observer;
    }

    bool anyEmpty()
    {
        foreach (queue; _queues)
        {
            if (queue.empty)
            {
                return true;
            }
        }
        return false;
    }

}

package(reactived):
template ElementTypes(TSources...) if (allSatisfy!(isObservable, TSources))
{
    static if (TSources.length == 1)
    {
        // When we have only one parameter, get its ElementType.
        // Note: it's not as simple as calling TSources[0].ElementType, 
        // since D won't allow it.  Nor cal we call 
        // (TSources[0]).ElementType, since that also causes a parse error.
        alias ElementTypes = AliasType!(TSources[0].ElementType);
    }
    else
    {
        // Recursively map the element types.
        alias ElementTypes = Variadic!(ElementTypes!(TSources[0]),
                Variadic!(ElementTypes!(TSources[1 .. $])));
    }
}

template QueueTypes(TElements...)
{
    static if (TElements.length == 1)
    {
        alias QueueTypes = AliasType!(LinkedQueue!(TElements[0]));
    }
    else
    {
        alias QueueTypes = Variadic!(QueueTypes!(TElements[0]),
                Variadic!(QueueTypes!(TElements[1 .. $])));
    }
}

template ObserverTypes(TElements...)
{
    static if (TElements.length == 1)
    {
        alias ObserverTypes = AliasType!(Observer!(TElements[0]));
    }
    else
    {
        alias ObserverTypes = Variadic!(ObserverTypes!(TElements[0]),
                Variadic!(ObserverTypes!(TElements[1 .. $])));
    }
}

template NotificationTypes(TElements...)
{
    static if (TElements.length == 1)
    {
        alias NotificationTypes = AliasType!(Notification!(TElements[0]));
    }
    else
    {
        alias NotificationTypes = Variadic!(NotificationTypes!(TElements[0]),
                Variadic!(NotificationTypes!(TElements[1 .. $])));
    }
}

template Variadic(TSources...)
{
    // For building the list back up.
    alias Variadic = TSources;
}

template AliasType(TResult)
{
    alias AliasType = TResult;
}

unittest
{
    just(1).and(just(2), just(3)).then!int((a, b, c) => a + b + c);
}
