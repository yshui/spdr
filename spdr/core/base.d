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

/// A vertex in a dependence graph
abstract class DepVertex
{
protected:
	/// An identifier for this vertex, if null, the content of this vertex won't be persisted
	/// **Has** to be unique
	string name_;

public:
	/// Persist the state of a vertex
	pure ubyte[] serialize() const
	{
		return [];
	}

	/// Restore vertex from saved state
	pure void deserialize(const(ubyte[]))
	{
	}

	/// Get the unique name of the vertex
	@safe final string name() const
	{
		return name_;
	}

	/// Calculate the hash of this vertex. Only used when dep vertex itself is return as value
	/// from a dep vertex
	@safe Hash calcHash() const
	{
		auto sha = makeDigest!SHA256;
		sha.put(cast(const(ubyte[])) name);
		return sha.finish;
	}
}

///
template DepBinOp(T, string op, S)
if (is(typeof(mixin("T.init" ~ op ~ "S.init"))))
{
alias Res = typeof(mixin("T.init"~op~"S.init"));
final static class DepBinOp :  Dep!(Res, Tuple!(T, S)) {
protected:
	override @safe Res nonrecursive_resolve(ref State s, Tuple!(T, S) operands)
	{
		return mixin("operands[0]" ~ op ~ "operands[1]");
	}

	mixin DepCtor!(Tuple!(T, S));
}
}

/// A vertex that returns value of type V, with indefinite dependencies
abstract class DepIndef(V) : DepVertex
{
public:
	/// Resolve this vertex. Will only be called after all of this vertex's dependencies
	/// have be resolved
	/// Returns a tuple of: 1) hash of the output, and 2) a value of type V.
	/// Note a vertex can always report itself as changed if it doesn't have cached results to compare with.
	@safe abstract Tuple!(Hash, V) resolve(ref State);

	DepIndef!V opBinary(string op, W)(DepIndef!W rhs) {
		return new DepBinOp!(V, op, W)(depTuple(this, rhs));
	}
	override string toString() {
		return name;
	}
}

unittest {
	auto a = "asdf".depConst, b = "qwer".depConst;
	auto c = a.opBinary!"~"(b);

	State s;
	import std.stdio;
	writeln(c.resolve(s));
}

private mixin template DepBase(bool impure, V, D...) if (D.length == 0 || D.length == 1)
{
	static if (D.length == 1)
	{
		DepIndef!(DepIndef!D) dep;
		///
		pure @trusted this(DepIndef!(DepIndef!D) d)
		{
			dep = d;
		}

		@disable this();
	}
	else
	{
		pure @trusted this()
		{
		}
	}
	@trusted override Tuple!(Hash, V) resolve(ref State s)
	{
		debug
		{
			import std.stdio : writeln;

			writeln("Resolving ", name);
		}
		static if (is(typeof(V.init.serializeToJson)))
		{
			debug pragma(msg, V.stringof ~ " is serializable");
			struct SerializeT
			{
				Hash hash;
				static if (impure && D.length == 1)
				{
					// In case of impure vertices, there are two distinct hashes
					Hash input_hash;
				}
				V val;
			}

			debug if (name in s.cache)
			{
				writeln(name, " found in cache");
			}
			if (cached.isNull && name in s.cache)
			{
				debug writeln("Restoring");
				auto dser = asdfDeserialize!SerializeT(s.cache[name].data);
				hash = dser.hash;
				cached = dser.val;
				static if (impure && D.length == 1)
				{
					input_hash = dser.input_hash;
				}
			}
		}
		else
		{
			debug pragma(msg, V.stringof ~ " is not serializable");
		}

		auto tmp = resolveImpl(s);

		static if (is(typeof(V.init.serializeToJson)))
		{
			static if (impure && D.length == 1)
			{
				SerializeT ser = SerializeT(hash, input_hash, tmp);
			}
			else
			{
				SerializeT ser = SerializeT(hash, tmp);
			}
			s.cache[name] = State.CacheEntry(!impure, ser.serializeToJson);
		}
		return tuple(hash, tmp);
	}
}

/// A vertex that returns value of type V, with dependency on value of type D
/// In actuality, this vertex will depend on DepIndef!(DepIndef!D) to allow dynamic dependencies
/// DepImpure.resolve will be called at least once per build even if the input dependencies didn't change.
abstract class DepImpure(V, D...) : DepIndef!V if (D.length == 0 || D.length == 1)
{
private:
	Hash input_hash; // The "input hash", created from hashes of dep
	Hash hash; // The "output hash"
	Nullable!V cached;
protected:
	/// Resolve this vertex itself assuming all its dependencies have been resolved
	@safe abstract Tuple!(Hash, V) nonrecursive_resolve(ref State, D);

	@safe V resolveImpl(ref State s)
	{
		static if (D.length == 1)
		{
			auto real_dep = dep.resolve(s);
			auto real_val = real_dep[1].resolve(s);
			if (cached.isNull || real_val[0] != input_hash)
			{
				input_hash = real_val[0];
				auto tmp = nonrecursive_resolve(s, real_val[1]);
				hash = tmp[0];
				cached = tmp[1];
			}
		}
		else
		{
			if (cached.isNull)
			{
				auto tmp = nonrecursive_resolve(s);
				hash = tmp[0];
				cached = tmp[1];
			}
		}
		return cached.get;
	}

public:
	mixin DepBase!(true, V, D);
}

/// Like Dep, but Dep's output purely depends on its input dependencies, whereas DepImpure's output can
/// have external dependencies
abstract class Dep(V, D...) : DepIndef!V if (D.length == 0 || D.length == 1)
{
private:
	Hash hash;
	Nullable!V cached;
protected:
	/// Resolve this vertex itself assuming all its dependencies have been resolved
	@safe abstract V nonrecursive_resolve(ref State, D);
	static if (D.length == 0)
	{
		static assert(is(typeof(V.init.calcHash()) == Hash),
				"type " ~ V.stringof
				~ " doesn't define an appropriate hash interface");
	}

	@safe V resolveImpl(ref State s)
	{
		static if (D.length == 1)
		{
			auto real_dep = dep.resolve(s);
			auto real_val = real_dep[1].resolve(s);
			if (cached.isNull || real_val[0] != hash)
			{
				hash = real_val[0];
				cached = nonrecursive_resolve(s, real_val[1]);
			}
		}
		else
		{
			if (cached.isNull)
			{
				cached = nonrecursive_resolve(s);
				hash = cached.calcHash();
			}
		}
		return cached.get;
	}

public:
	mixin DepBase!(false, V, D);
}

///
mixin template DepCtor(D...)
{
	static if (D.length == 1)
	{
		///
		public @safe this(DepIndef!(DepIndef!D) d)
		{
			super(d);
			this.name_ = typeof(this).stringof ~ "(" ~ d.name ~ ")";
		}

		public @safe this(DepIndef!D d)
		{
			this(d.depConst);
		}

		@disable this();
	}
}

///
final class DepConst(T) : Dep!T
{
private:
	T val;
	static assert(is(typeof(T.init.calcHash()) == Hash),
			"type " ~ T.stringof ~ " doesn't define an appropriate hash interface");
public:
	override T nonrecursive_resolve(ref State s)
	{
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
		name_ = format!("DepConst!(" ~ T.stringof ~ ")(%s)")(inner_name);
	}

	override string toString() const
	{
		return name;
	}
}

/// Helper for creating DepConst
auto depConst(T)(auto ref T val)
{
	return new DepConst!T(val);
}

alias DepUnwrap(T : DepIndef!V, V) = V;

/// Create a vertex that returns Tuple!(A, B, C, D...) from a tuple of vertices which are
/// AliasSeq!(DepIndef!A, DepIndef!B, DepIndef!C, DepIndef!D, ...)
final class DepTuple(S...) : DepIndef!(Tuple!(staticMap!(DepUnwrap, S)))
{
private:
	import std.traits : ConstOf;

	alias inner = staticMap!(DepUnwrap, S);
	Tuple!S deps;
public:
	override Tuple!(Hash, Tuple!inner) resolve(ref State s)
	{
		Tuple!inner retv;
		auto sha = makeDigest!SHA256;
		foreach (i, d; deps)
		{
			auto tmp = d.resolve(s);
			retv[i] = tmp[1];
			sha.put(tmp[0]);
		}
		return tuple(sha.finish, retv);
	}
	///
	this(S _deps)
	{
		import std.conv : to;

		deps = Tuple!S(_deps);
		name_ = "DepTuple!(" ~ S.stringof ~ ")(" ~ [_deps].to!string ~ ")";
	}

	override string toString() const
	{
		return name;
	}
}

/// Helper for creating DepTuple
auto depTuple(S...)(S deps)
{
	return new DepTuple!S(deps);
}

/// Create a vertex that is DepInfdef!(T[]) from an array of DepInfdef!T vertices
final class DepArray(S) : DepIndef!(DepUnwrap!S[])
{
private:
	alias T = DepUnwrap!S;
	T[] inner;
	S[] deps;
public:
	override Tuple!(Hash, DepUnwrap!S[]) resolve(ref State s)
	{
		T[] ret;
		auto sha = makeDigest!SHA256;
		foreach (i, d; deps)
		{
			auto tmp = d.resolve(s);
			ret ~= tmp[1];
			sha.put(tmp[0]);
		}
		return tuple(sha.finish, ret);
	}

	///
	this(S[] _deps)
	{
		import std.conv : to;

		deps = _deps;
		name_ = "DepArray!(" ~ S.stringof ~ "[])(" ~ deps.to!string ~ ")";
	}

	override string toString() const
	{
		return name;
	}
}

///
auto depArray(S)(S[] deps)
{
	return new DepArray!S(deps);
}

///
auto depUpCast(S : DepIndef!T, T)(S i)
{
	return cast(DepIndef!T) i;
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

	State s;

	import std.stdio : writeln;

	auto x = new DepConst!TestT1(TestT1(1, 2));
	assert(x.nonrecursive_resolve(s) == TestT1(1, 2));

	auto y = new DepConst!TestT1(TestT1(2, 3));
	assert(y.nonrecursive_resolve(s) == TestT1(2, 3));

	auto z = depTuple(x, y);
	assert(z.resolve(s)[1][0] == x.nonrecursive_resolve(s));
	assert(z.resolve(s)[1][1] == y.nonrecursive_resolve(s));
	writeln(z.name);

	auto w = depArray([x, y]);
	assert(w.resolve(s)[1][0] == x.nonrecursive_resolve(s));
	assert(w.resolve(s)[1][1] == y.nonrecursive_resolve(s));

	auto a = depConst(cast(DepIndef!(TestT1[])) w);
	writeln(a.name);
}
