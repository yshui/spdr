module spdr.core.base;
import std.typecons;
import std.range.interfaces;
import std.digest.sha;
import std.digest : makeDigest;
import std.meta : staticMap;
import std.traits : isIntegral;
import asdf.serialization : serializeToJson, asdfDeserialize = deserialize;

///
struct State
{
	///
	struct CacheEntry
	{
		/// Whether this entry should be persisted
		bool persistent;
		///
		string data;
	}

	///
	CacheEntry[string] cache;
}

alias Hash = ubyte[32];

/// A task that represents doing a binary operation on the results of two other tasks
template BinOpTask(T, string op, S)
if (is(typeof(mixin("T.init" ~ op ~ "S.init"))))
{
alias Res = typeof(mixin("T.init"~op~"S.init"));
final static class BinOpTask :  TaskBase!Res {
protected:
	Res value_;
public:
	override void resolve()
	{
		auto lhs = dep.value.value[0];
		auto rhs = dep.value.value[1];
		mixin("value_ = lhs" ~ op ~ "rhs;");
		resolved_ = true;
	}

	override ref const(Hash) hash() const {
		return dep.value.hash;
	}

	override inout(Res) value() inout {
		return value_;
	}
	mixin DependentTaskMixin!(Tuple!(S, T));
}
}

/// A task that returns value of type V, with indefinite dependencies
abstract class UntypedTaskBase
{
protected:
	/// An identifier for this task, if null, the state of this task won't be persisted
	/// **Must** be unique
	string name_;
	bool resolved_;
public:
	@safe pure @property bool resolved() const {
		return resolved_;
	}
	/// Resolve this vertex. Will only be called after all of this vertex's dependencies
	/// have be resolved
	/// Returns a tuple of: 1) hash of the output, and 2) a value of type V.
	@safe void resolve() out (; resolved) {}

	override string toString() {
		return name;
	}

	/// Persist the state of a vertex
	pure ubyte[] serialize() const
	{
		return [];
	}

	/// Restore the task from saved state. Returns true if the state is restored. That
	/// is, this task has been restored to a state as if resolve() has been called.
	/// Returns false otherwise.
	pure bool deserialize(const(ubyte[]))
	{
		return false;
	}

	/// Get the unique name of the vertex
	@safe string name() const
	{
		return name_;
	}

	@safe UntypedTaskBase getDependencyTask() {
		return null;
	}

	/// Get dependencies of this task, the task returned by `getDependencyTask` must
	/// be resolved before calling this function
	@safe UntypedTaskBase[] getDependencies() {
		return [];
	}

	/// Get a hash representing the current state of the task. Only called when resolve()
	/// has finished. Could throw if called before resolve
	@safe abstract ref const(Hash) hash() const in (resolved) out (; resolved);

	/// Calculate the hash representing this task (not the state or output of this task!).
	/// This is meant to be used as a unique identifier of the task itself, not what this
	/// task resolves to.
	@safe Hash calcHash() const {
		return name.calcHash;
	}
}

abstract class TaskBase(V) : UntypedTaskBase {
public:
	alias Output = V;
	/// Get the resolved value of the task
	@safe abstract inout(V) value() inout in (resolved) out (; resolved);

	TaskBase!V opBinary(string op, W)(TaskBase!W rhs) {
		return new BinOpTask!(V, op, W)(taskJoin(this, rhs));
	}
}

unittest {
	auto a = "asdf".toConstTask, b = "qwer".toConstTask;
	auto c = a.opBinary!"~"(b);

	import std.stdio;
	c.recursivelyResolve;
	writeln(c.value);
}

mixin template DependentTaskMixin(D...) if (D.length == 0 || D.length == 1)
{
	static if (D.length == 1)
	{
		/// A task that returns the dependencies for this task. We don't use a direct
		/// dependency task directly since we want to support dynamic dependencies
		protected TaskBase!(TaskBase!D) dep;
		///
		public @safe this(TaskBase!(TaskBase!D) d)
		{
			dep = d;
			this.name_ = typeof(this).stringof ~ "(" ~ d.name ~ ")";
		}

		public @safe this(TaskBase!D d)
		{
			this(d.toConstTask);
		}

		public @disable this();
	}
	else
	{
		public pure @trusted this()
		{
		}
	}

	override UntypedTaskBase getDependencyTask() {
		return dep;
	}

	override UntypedTaskBase[] getDependencies() {
		return [ cast(UntypedTaskBase)dep.value ];
	}
}

///
final class ConstTask(T) : TaskBase!T
{
private:
	T val;
	//static assert(is(typeof(T.init.calcHash) == Hash),
			//"type " ~ T.stringof ~ " doesn't define an appropriate hash interface");
	Hash hash_;
public:
	override void resolve() {
		hash_ = val.calcHash;
		resolved_ = true;
	}
	override ref const(Hash) hash() const in (resolved) {
		return hash_;
	}

	override inout(T) value() inout in (resolved) {
		return val;
	}
	///
	@trusted this()(auto ref T v)
	{
		import std.format : format;

		val = v;

		string inner_name;
		static if (is(typeof(val.name)))
		{
			inner_name = val.name;
		} else
		{
			import std.conv : to;
			inner_name = val.to!string;
		}
		name_ = format!("ConstTask!(" ~ T.stringof ~ ")(%s)")(inner_name);
	}
}

/// Helper for creating DepConst
auto toConstTask(T)(auto ref T val)
{
	return new ConstTask!T(val);
}

alias getTaskOutput(T : TaskBase!V, V) = V;

auto mapTuple(alias fun, T...)(Tuple!T arg) {
    import std.conv : text;
    import std.range : iota;
    import std.algorithm.iteration : joiner, map;
    import std.functional : unaryFun;

    alias fn = unaryFun!fun;
    return mixin(text("tuple(",T.length.iota.map!(i => text("fn(arg[",i,"])")).joiner(","),")"));
}

import std.traits : ConstOf;
/// Create a vertex that returns Tuple!(A, B, C, D...) from a tuple of vertices which are
/// AliasSeq!(DepIndef!A, DepIndef!B, DepIndef!C, DepIndef!D, ...)
final class TaskTuple(S...) : TaskBase!(Tuple!(staticMap!(getTaskOutput, S)))
{
private:

	alias inner = staticMap!(getTaskOutput, S);
	Hash hash_;
	Tuple!inner value_;
	Tuple!S deps;
public:
	override void resolve() {
		import std.algorithm : move;
		value_ = deps.mapTuple!"a.value";
		auto sha = makeDigest!SHA256;
		foreach (d; deps)
		{
			sha.put(d.hash);
		}
		hash_ = sha.finish;
		resolved_ = true;
	}
	override @trusted inout(Tuple!inner) value() inout in (resolved) {
		return value_;
	}
	override ref const(Hash) hash() const in (resolved) {
		return hash_;
	}

	override UntypedTaskBase[] getDependencies() {
		import std.range : put;
		UntypedTaskBase[] ret;
		foreach(d; deps) {
			ret ~= d;
		}
		return ret;
	}

	///
	this(S _deps)
	{
		import std.conv : to;

		deps = Tuple!S(_deps);
		name_ = "TaskTuple!(" ~ S.stringof ~ ")(" ~ [_deps].to!string ~ ")";
	}
}

/// Helper for creating DepTuple
auto taskJoin(S...)(S deps)
{
	return new TaskTuple!S(deps);
}

/// Create a task that generate a T[] from an array of tasks that generate T
final class TaskArray(S) : TaskBase!(getTaskOutput!S[])
{
private:
	alias T = getTaskOutput!S;
	T[] inner;
	S[] deps;
	Hash hash_;
public:
	override void resolve() {
		import std.range : put;
		foreach(d; deps) {
			inner ~= d.value;
		}

		auto sha = makeDigest!SHA256;
		foreach (d; deps)
		{
			sha.put(d.hash);
		}
		hash_ = sha.finish;
		resolved_ = true;
	}
	override inout(T[]) value() inout in (resolved) {
		return inner;
	}

	override ref const(Hash) hash() const in (resolved) {
		return hash_;
	}

	///
	this(S[] _deps)
	{
		import std.conv : to;

		deps = _deps;
		name_ = "TaskArray!(" ~ S.stringof ~ "[])(" ~ deps.to!string ~ ")";
	}
}

///
auto taskArray(S)(S[] deps)
{
	return new TaskArray!S(deps);
}

///
auto taskUpCast(S : TaskBase!T, T)(S i)
{
	return cast(TaskBase!T) i;
}

///
@trusted Hash calcHash(const(string) i)
{
	auto sha = makeDigest!SHA256;
	sha.put(cast(const(ubyte)[]) i);
	return sha.finish();
}

///
@trusted Hash calcHash(const(string[]) i)
{
	auto sha = makeDigest!SHA256;
	foreach (x; i)
	{
		sha.put(cast(const(ubyte)[]) x);
	}
	return sha.finish();
}

/// ditto
@trusted Hash calcHash(T)(T x) if (isIntegral!T)
{
	auto sha = makeDigest!SHA256;
	sha.put(cast(const(ubyte[]))[x]);
	return sha.finish;
}

@trusted Hash calcHash(T)(const(T[]) x) if (is(typeof(T.init.calcHash))) {
	auto sha = makeDigest!SHA256;
	foreach(d; x) {
		sha.put(x.calcHash[]);
	}
	return sha.finish;
}

void recursivelyResolve(UntypedTaskBase task) {
	if (task is null) {
		return;
	}
	if (task.resolved) {
		return;
	}

	recursivelyResolve(task.getDependencyTask);
	foreach(d; task.getDependencies) {
		recursivelyResolve(d);
	}
	task.resolve;
}

unittest
{
	///
	static struct TestT1
	{
		int a, b;
		@trusted Hash calcHash() const
		{
			auto sha = makeDigest!SHA256;
			sha.put(cast(ubyte[])[a, b]);
			return sha.finish;
		}
	}

	import std.stdio : writeln;

	auto x = TestT1(1, 2).toConstTask;
	x.recursivelyResolve;

	auto y = TestT1(2, 3).toConstTask;
	y.recursivelyResolve;
	assert(y.value == TestT1(2, 3));

	auto z = x.taskJoin(y);
	z.recursivelyResolve;
	assert(z.value[0] == x.value);
	assert(z.value[1] == y.value);
	writeln(z.name);

	auto w = taskArray([x, y]);
	w.recursivelyResolve;
	assert(w.value[0] == x.value);
	assert(w.value[1] == y.value);

	auto a = toConstTask(w.taskUpCast);
	writeln(a.name);
}
