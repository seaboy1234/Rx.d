module reactived.scheduler;

import reactived;
import reactived.observer;
import std.traits;

interface Scheduler
{
    void run(void delegate() dg);
}

template isScheduler(T)
{
    private void test()
    {
    }

    enum isScheduler = typeof({ T s = T.init; s.run(() => {  }); s.run(&test); });
}

class DefaultScheduler : Scheduler
{
    void run(void delegate() dg)
    {
        dg();
    }
}

unittest
{
    bool safe;

    Scheduler s = new DefaultScheduler();

    void test()
    {
        safe = true;
    }

    s.run(&test);

    assert(safe);
}

import std.parallelism : task, taskPool, TaskPool;

class TaskScheduler : Scheduler
{

    private TaskPool _pool;

    this()
    {
        this(taskPool());
    }

    this(TaskPool pool)
    {
        _pool = pool;
    }

    void run(void delegate() dg)
    {
        // This is a workaround to a strange compiler error which was 
        // complaining that Task could not access the frame of `run`. 
        static void call(void delegate() dg)
        {
            dg();
        }

        auto t = task!call(dg);

        _pool.put(t);
    }
}

unittest
{
    bool safe;

    Scheduler s = new TaskScheduler();

    void test()
    {
        safe = true;
    }

    s.run(&test);

    import core.thread : Thread;
    import std.datetime : dur;

    Thread.sleep(dur!"msecs"(100));

    assert(safe);
}

class NewThreadScheduler : Scheduler
{
    void run(void delegate() dg)
    {
        import core.thread : Thread;

        new Thread(dg).start();
    }
}

unittest
{
    import core.thread : Thread;

    bool safe;
    size_t tid = Thread.getThis().id;

    Scheduler s = new NewThreadScheduler();

    void test()
    {
        assert(tid != Thread.getThis().id);
        safe = true;
    }

    s.run(&test);

    import std.datetime : dur;

    Thread.sleep(dur!"msecs"(100));

    assert(safe);
}

class ScheduledObserver(T) : Observer!T
{
    private Scheduler _scheduler;
    private Observer!T _observer;

    this(Observer!T observer, Scheduler scheduler)
    {
        import std.exception : enforce;

        enforce(scheduler !is null);
        enforce(observer !is null);

        _observer = observer;
        _scheduler = scheduler;
    }

    void onNext(T value)
    {
        _scheduler.run(() { _observer.onNext(value); });
    }

    void onCompleted()
    {
        _scheduler.run(() { _observer.onCompleted(); });
    }

    void onError(Throwable error)
    {
        _scheduler.run(() { _observer.onError(error); });
    }
}

/**
    Instructs the Observable to forward notifications to the specified scheduler.

    See_Also:
    subscribeOn
*/
Observable!T observeOn(T)(Observable!T observable, Scheduler scheduler)
{
    Disposable subscribe(Observer!T observer)
    {
        return observable.subscribe(new ScheduledObserver!T(observer, scheduler));
    }

    return create(&subscribe);
}

///
unittest
{
    import core.thread : Thread;
    import reactived.util : dump;

    size_t tid = Thread.getThis().id;

    Observable!int o = create((Observer!int observer) {
        assert(tid == Thread.getThis().id);

        observer.onNext(1);
        observer.onNext(2);
        observer.onNext(3);

        observer.onCompleted();
        return empty();
    });

    o.observeOn(new NewThreadScheduler()).take(1).dump("observeOn()");
}

/**
    Uses the provided Scheduler to call the Observable's subscribe method.  The Observable's work will then be executed on the scheduler.

    This function is useful for moving the observable's work off of, say, the UI Thread and delegating time-intensive work to a different thread.

    See_Also: 
    observeOn
*/
Observable!T subscribeOn(T)(Observable!T observable, Scheduler scheduler)
{
    Disposable subscribe(Observer!T observer)
    {
        Disposable disposable;
        scheduler.run(() { disposable = observable.subscribe(observer); });
        return createDisposable(() => disposable.dispose());
    }

    return create(&subscribe);
}

///
unittest
{
    import core.thread : Thread;
    import reactived.util : dump;

    size_t tid = Thread.getThis().id;

    Observable!int o = create((Observer!int observer) {
        assert(tid != Thread.getThis().id);

        observer.onNext(1);
        observer.onNext(2);
        observer.onNext(3);

        observer.onCompleted();
        return empty();
    });

    o.subscribeOn(new NewThreadScheduler()).take(1).dump("subscribeOn()");
}